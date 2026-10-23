package com.saoshu.xindian;

import android.content.SharedPreferences;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.Date;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Random;
import java.util.Set;
import java.util.TimeZone;

/**
 * Native port of BookSift's incremental Tieba collection pipeline.
 *
 * Network protocol, endpoint and protobuf field mapping follow BookSift's
 * frs/page and pb/page implementation. The host app owns classification,
 * document ingestion and UI; this class owns forum watermarks, anonymous rate
 * limiting, retries, cooldown and protobuf parsing.
 */
final class TiebaCollector {
    static final String SOURCE_KIND = "tieba_network";
    static final String PREF_THREADS = "tieba_collect_threads";
    static final String PREF_COLD_THREADS = "tieba_collect_cold_threads";
    static final String PREF_FLOORS = "tieba_collect_floors";
    static final String PREF_LIST_PAGES = "tieba_collect_list_pages";
    private static final String HOST = "https://tiebac.baidu.com";
    private static final String USER_AGENT = "aiotieba/22.12.1.0";
    private static final String CLIENT_VERSION = "12.64.1.1";
    private static final String BOUNDARY = "-*_r1999";
    private static final int FRS_CMD = 301001;
    private static final int PB_CMD = 302001;
    private static final int LIST_PAGE_SIZE = 50;
    private static final int POST_PAGE_SIZE = 30;
    private static final int MAX_POST_PAGES = 20;
    private static final int DAILY_BUDGET = 300;
    private static final int FORUM_FAILURE_LIMIT = 3;
    private static final long COOLDOWN_MS = 48L * 60L * 60L * 1000L;

    interface Listener {
        void onStatus(String text, int progress);

        void onLog(String fname, String event, String detail);
    }

    static final class ForumScan {
        final String fname;
        final boolean complete;
        final boolean cooldown;
        final String error;

        ForumScan(String fname, boolean complete, boolean cooldown, String error) {
            this.fname = fname;
            this.complete = complete;
            this.cooldown = cooldown;
            this.error = safe(error);
        }
    }

    static final class CollectionSession {
        final List<CollectedThread> threads;
        final Map<String, ForumScan> forums;
        final int requests;
        final int failedForums;
        final long finishedAt;

        CollectionSession(List<CollectedThread> threads,
                          Map<String, ForumScan> forums,
                          int requests, int failedForums, long finishedAt) {
            this.threads = threads;
            this.forums = forums;
            this.requests = requests;
            this.failedForums = failedForums;
            this.finishedAt = finishedAt;
        }
    }

    static final class Floor {
        final long pid;
        final int seq;
        final int time;
        final int agree;
        final String author;
        final String text;

        Floor(long pid, int seq, int time, int agree, String author, String text) {
            this.pid = pid;
            this.seq = seq;
            this.time = time;
            this.agree = agree;
            this.author = author;
            this.text = text;
        }
    }

    static final class CollectedThread {
        final String forum;
        final long tid;
        final String title;
        final String author;
        final int createTime;
        final int lastTime;
        final int replyNum;
        final int viewNum;
        final List<Floor> floors;

        CollectedThread(String forum, long tid, String title, String author,
                        int createTime, int lastTime, int replyNum, int viewNum,
                        List<Floor> floors) {
            this.forum = forum;
            this.tid = tid;
            this.title = title;
            this.author = author;
            this.createTime = createTime;
            this.lastTime = lastTime;
            this.replyNum = replyNum;
            this.viewNum = viewNum;
            this.floors = floors;
        }

        int maxAgree() {
            int result = 0;
            for (Floor floor : floors) {
                result = Math.max(result, floor.agree);
            }
            return result;
        }

        String combinedText() {
            StringBuilder builder = new StringBuilder();
            for (Floor floor : floors) {
                String text = floor.text == null ? "" : floor.text.trim();
                if (text.isEmpty()) {
                    continue;
                }
                if (builder.length() > 0) {
                    builder.append("\n\n");
                }
                if (floor.seq > 1) {
                    builder.append("第").append(floor.seq).append("楼");
                    if (!floor.author.isEmpty()) {
                        builder.append(" · ").append(floor.author);
                    }
                    builder.append('\n');
                }
                builder.append(text);
            }
            return builder.toString().trim();
        }
    }

    private static final class ThreadSummary {
        final long tid;
        final String title;
        final String author;
        final int createTime;
        final int lastTime;
        final boolean top;
        final boolean deleted;
        final boolean masked;

        ThreadSummary(long tid, String title, String author, int createTime,
                      int lastTime, boolean top, boolean deleted, boolean masked) {
            this.tid = tid;
            this.title = title;
            this.author = author;
            this.createTime = createTime;
            this.lastTime = lastTime;
            this.top = top;
            this.deleted = deleted;
            this.masked = masked;
        }
    }

    private static final class ThreadsPage {
        final long fid;
        final boolean hasMore;
        final List<ThreadSummary> threads;

        ThreadsPage(long fid, boolean hasMore, List<ThreadSummary> threads) {
            this.fid = fid;
            this.hasMore = hasMore;
            this.threads = threads;
        }
    }

    private static final class PostsPage {
        final boolean hasMore;
        final String title;
        final String author;
        final int createTime;
        final int replyNum;
        final int viewNum;
        final List<Floor> floors;

        PostsPage(boolean hasMore, String title, String author, int createTime,
                  int replyNum, int viewNum, List<Floor> floors) {
            this.hasMore = hasMore;
            this.title = title;
            this.author = author;
            this.createTime = createTime;
            this.replyNum = replyNum;
            this.viewNum = viewNum;
            this.floors = floors;
        }
    }

    private static final class ForumState {
        final String fname;
        long fid;
        boolean enabled;
        long lastThreadTime;
        long lastTid;
        int consecutiveFailures;
        long cooldownUntil;
        long totalThreads;
        long totalFloors;

        ForumState(String fname, long fid, boolean enabled, long lastThreadTime,
                   long lastTid, int consecutiveFailures, long cooldownUntil,
                   long totalThreads, long totalFloors) {
            this.fname = fname;
            this.fid = fid;
            this.enabled = enabled;
            this.lastThreadTime = lastThreadTime;
            this.lastTid = lastTid;
            this.consecutiveFailures = consecutiveFailures;
            this.cooldownUntil = cooldownUntil;
            this.totalThreads = totalThreads;
            this.totalFloors = totalFloors;
        }
    }

    private static final class CollectException extends Exception {
        final boolean rateLimited;
        final int code;

        CollectException(String message, boolean rateLimited, int code) {
            super(message);
            this.rateLimited = rateLimited;
            this.code = code;
        }
    }

    private static final class BudgetException extends Exception {
    }

    private static final class CanceledException extends Exception {
    }

    private final SQLiteDatabase db;
    private final SharedPreferences preferences;
    private final Listener listener;
    private final String bduss;
    private final int configuredThreads;
    private final int configuredColdThreads;
    private final int configuredFloors;
    private final int configuredListPages;
    private final Random random = new Random();
    private volatile boolean canceled;
    private int requestCount;
    private long lastRequestAt;

    TiebaCollector(SQLiteDatabase db, SharedPreferences preferences,
                   Listener listener, String bduss) {
        this.db = db;
        this.preferences = preferences;
        this.listener = listener;
        this.bduss = safe(bduss);
        configuredThreads = clamp(preferences.getInt(PREF_THREADS, 20), 1, 50);
        configuredColdThreads = clamp(
                preferences.getInt(PREF_COLD_THREADS, 8), 1, 50);
        configuredFloors = clamp(
                preferences.getInt(PREF_FLOORS, 150), 1, 300);
        configuredListPages = clamp(
                preferences.getInt(PREF_LIST_PAGES, 3), 1, 5);
    }

    void cancel() {
        canceled = true;
    }

    CollectionSession collect() throws Exception {
        try {
            ensureForums();
            List<ForumState> forums = loadForums();
            if (forums.isEmpty()) {
                throw new IllegalStateException("没有启用的贴吧");
            }
            List<CollectedThread> threads = new ArrayList<>();
            Map<String, ForumScan> scans = new HashMap<>();
            int failedForums = 0;
            int enabledCount = 0;
            for (ForumState forum : forums) {
                if (!forum.enabled) {
                    continue;
                }
                enabledCount++;
            }
            if (enabledCount == 0) {
                throw new IllegalStateException("没有启用的贴吧");
            }
            log("全局", "参数", "每吧 " + configuredThreads +
                    " 帖 · 冷启动 " + configuredColdThreads +
                    " 帖 · 每帖 " + configuredFloors +
                    " 楼 · 列表 " + configuredListPages + " 页");
            int forumIndex = 0;
            for (ForumState forum : forums) {
                if (!forum.enabled) {
                    continue;
                }
                throwIfCanceled();
                if (forum.cooldownUntil > System.currentTimeMillis()) {
                    log(forum.fname, "跳过",
                            "失败冷却中至 " + formatTime(forum.cooldownUntil));
                    scans.put(forum.fname,
                            new ForumScan(forum.fname, false, true, "失败冷却中"));
                    forumIndex++;
                    continue;
                }
                listener.onStatus("正在读取 " + forum.fname + " 新帖列表…",
                        forumIndex * 100 / Math.max(1, enabledCount));
                ForumPreview preview = collectForum(
                        forum, forumIndex, enabledCount);
                threads.addAll(preview.threads);
                scans.put(forum.fname, preview.scan);
                if (!preview.scan.complete) {
                    failedForums++;
                }
                forumIndex++;
            }
            listener.onStatus("网络采集完成", 100);
            return new CollectionSession(threads, scans,
                    requestCount, failedForums,
                    System.currentTimeMillis());
        } catch (BudgetException error) {
            throw new IllegalStateException("今日贴吧请求预算已用完", error);
        } catch (CanceledException error) {
            throw new IllegalStateException("网络采集已停止", error);
        }
    }

    private static final class ForumPreview {
        final ForumScan scan;
        final List<CollectedThread> threads;

        ForumPreview(ForumScan scan, List<CollectedThread> threads) {
            this.scan = scan;
            this.threads = threads;
        }
    }

    private ForumPreview collectForum(ForumState forum, int forumIndex, int forumCount)
            throws Exception {
        List<CollectedThread> collected = new ArrayList<>();
        boolean cold = forum.lastThreadTime <= 0;
        int maxPages = configuredListPages;
        int maxThreads = cold
                ? Math.min(configuredThreads, configuredColdThreads)
                : configuredThreads;
        List<ThreadSummary> queue = new ArrayList<>();
        boolean stopScan = false;
        try {
            for (int pageNo = 1; pageNo <= maxPages && !stopScan; pageNo++) {
                throwIfCanceled();
                listener.onStatus("正在读取 " + forum.fname + " 列表 " +
                                pageNo + "/" + maxPages,
                        (forumIndex * 100 + pageNo * 20) / Math.max(1, forumCount));
                ThreadsPage page = requestThreadsWithRetry(forum.fname, pageNo);
                if (page.fid > 0 && page.fid != forum.fid) {
                    forum.fid = page.fid;
                    updateForumFid(forum.fname, forum.fid);
                }
                for (ThreadSummary thread : page.threads) {
                    if (thread.top || thread.deleted || thread.masked) {
                        continue;
                    }
                    if (forum.lastThreadTime <= 0
                            || thread.createTime > forum.lastThreadTime
                            || (thread.createTime == forum.lastThreadTime
                            && thread.tid > forum.lastTid)) {
                        queue.add(thread);
                        if (cold && queue.size() >= maxThreads) {
                            stopScan = true;
                            break;
                        }
                    } else if (!cold) {
                        stopScan = true;
                    }
                }
                log(forum.fname, "列表", "第 " + pageNo + " 页 " +
                        page.threads.size() + " 帖，累计新帖 " + queue.size());
                if (!page.hasMore) {
                    break;
                }
            }
            Collections.sort(queue, new Comparator<ThreadSummary>() {
                @Override
                public int compare(ThreadSummary left, ThreadSummary right) {
                    return Integer.compare(left.createTime, right.createTime);
                }
            });
            if (queue.size() > maxThreads) {
                queue = new ArrayList<>(queue.subList(queue.size() - maxThreads, queue.size()));
            }
            int failures = 0;
            int processed = 0;
            for (ThreadSummary summary : queue) {
                throwIfCanceled();
                processed++;
                listener.onStatus("正在采集 " + forum.fname + " · " +
                                processed + "/" + queue.size(),
                        (forumIndex * 100 + 20 + (70 * processed /
                                Math.max(1, queue.size()))) / Math.max(1, forumCount));
                try {
                    CollectedThread thread = fetchThread(forum.fname, summary);
                    collected.add(thread);
                    log(forum.fname, "待导入", "tid=" + summary.tid +
                            " · " + thread.title + " · 楼层=" + thread.floors.size());
                    failures = 0;
                } catch (BudgetException | CanceledException error) {
                    throw error;
                } catch (CollectException error) {
                    failures++;
                    log(forum.fname, "失败", "tid=" + summary.tid + " · " +
                            error.getMessage());
                    if (failures >= FORUM_FAILURE_LIMIT) {
                        return new ForumPreview(new ForumScan(
                                forum.fname, false, false, error.getMessage()),
                                collected);
                    }
                } catch (Exception error) {
                    log(forum.fname, "失败", "tid=" + summary.tid + " · " +
                            readable(error));
                    return new ForumPreview(new ForumScan(
                            forum.fname, false, false, readable(error)),
                            collected);
                }
            }
            log(forum.fname, "预览", "已获取 " + collected.size() +
                    " 个帖子，等待用户选择导入");
            return new ForumPreview(new ForumScan(
                    forum.fname, true, false, ""), collected);
        } catch (BudgetException error) {
            throw error;
        } catch (CanceledException error) {
            throw error;
        } catch (CollectException error) {
            log(forum.fname, "失败", error.getMessage());
            return new ForumPreview(new ForumScan(
                    forum.fname, false, false, error.getMessage()), collected);
        }
    }

    private CollectedThread fetchThread(String fname, ThreadSummary summary)
            throws Exception {
        List<Floor> floors = new ArrayList<>();
        Set<Long> seen = new LinkedHashSet<>();
        String title = summary.title;
        String author = summary.author;
        int createTime = summary.createTime;
        int replyNum = 0;
        int viewNum = 0;
        int postPages = Math.min(MAX_POST_PAGES,
                (configuredFloors + POST_PAGE_SIZE - 1) / POST_PAGE_SIZE);
        for (int pageNo = 1; pageNo <= postPages; pageNo++) {
            throwIfCanceled();
            PostsPage page = requestPostsWithRetry(summary.tid, pageNo);
            if (!page.title.trim().isEmpty()) {
                title = page.title;
            }
            if (!page.author.trim().isEmpty()) {
                author = page.author;
            }
            if (page.createTime > 0) {
                createTime = page.createTime;
            }
            replyNum = Math.max(replyNum, page.replyNum);
            viewNum = Math.max(viewNum, page.viewNum);
            for (Floor floor : page.floors) {
                if (floor.pid == 0 || seen.add(floor.pid)) {
                    floors.add(floor);
                }
            }
            if (floors.size() >= configuredFloors || !page.hasMore) {
                break;
            }
        }
        if (floors.size() > configuredFloors) {
            floors = new ArrayList<>(
                    floors.subList(0, configuredFloors));
        }
        Collections.sort(floors, new Comparator<Floor>() {
            @Override
            public int compare(Floor left, Floor right) {
                return Integer.compare(left.seq, right.seq);
            }
        });
        return new CollectedThread(fname, summary.tid, title, author,
                createTime, summary.lastTime, replyNum, viewNum, floors);
    }

    private ThreadsPage requestThreadsWithRetry(String fname, int page)
            throws Exception {
        CollectException last = null;
        for (int attempt = 0; attempt < 3; attempt++) {
            try {
                return requestThreads(fname, page);
            } catch (CollectException error) {
                last = error;
                if (attempt < 2) {
                    sleep((attempt + 1L) * 5_000L);
                }
            }
        }
        throw last == null ? new CollectException("列表请求失败", false, 0) : last;
    }

    private PostsPage requestPostsWithRetry(long tid, int page)
            throws Exception {
        CollectException last = null;
        for (int attempt = 0; attempt < 2; attempt++) {
            try {
                return requestPosts(tid, page);
            } catch (CollectException error) {
                last = error;
                if (attempt == 0) {
                    sleep(5_000L);
                }
            }
        }
        throw last == null ? new CollectException("楼层请求失败", false, 0) : last;
    }

    private ThreadsPage requestThreads(String fname, int page)
            throws Exception {
        int apiPage = page <= 1 ? 0 : page;
        TiebaProto.Writer common = commonRequest();
        TiebaProto.Writer data = new TiebaProto.Writer()
                .message(39, common)
                .text(1, fname)
                .varint(2, LIST_PAGE_SIZE)
                .varint(3, LIST_PAGE_SIZE + 5)
                .varint(4, 0)
                .varint(15, apiPage)
                .varint(47, 1);
        byte[] request = new TiebaProto.Writer().message(1, data).bytes();
        byte[] response = postProto("/c/f/frs/page?cmd=" + FRS_CMD, request);
        return parseThreads(response);
    }

    private PostsPage requestPosts(long tid, int page) throws Exception {
        TiebaProto.Writer common = commonRequest();
        TiebaProto.Writer data = new TiebaProto.Writer()
                .message(25, common)
                .varint(4, tid)
                .varint(5, 0)
                .varint(6, 0)
                .varint(13, POST_PAGE_SIZE)
                .varint(18, page);
        byte[] request = new TiebaProto.Writer().message(1, data).bytes();
        byte[] response = postProto("/c/f/pb/page?cmd=" + PB_CMD, request);
        return parsePosts(response);
    }

    private TiebaProto.Writer commonRequest() {
        TiebaProto.Writer common = new TiebaProto.Writer()
                .varint(1, 2)
                .text(2, CLIENT_VERSION);
        if (!bduss.isEmpty()) {
            common.text(10, bduss);
        }
        return common;
    }

    private byte[] postProto(String path, byte[] protobuf) throws Exception {
        throttle();
        byte[] head = ("--" + BOUNDARY + "\r\n"
                + "Content-Disposition: form-data; name=\"data\"; filename=\"file\"\r\n"
                + "\r\n").getBytes(StandardCharsets.UTF_8);
        byte[] tail = ("\r\n--" + BOUNDARY + "--\r\n")
                .getBytes(StandardCharsets.UTF_8);
        byte[] body = new byte[head.length + protobuf.length + tail.length];
        System.arraycopy(head, 0, body, 0, head.length);
        System.arraycopy(protobuf, 0, body, head.length, protobuf.length);
        System.arraycopy(tail, 0, body, head.length + protobuf.length, tail.length);

        HttpURLConnection connection = null;
        try {
            connection = (HttpURLConnection) new URL(HOST + path).openConnection();
            connection.setConnectTimeout(15_000);
            connection.setReadTimeout(30_000);
            connection.setRequestMethod("POST");
            connection.setDoOutput(true);
            connection.setInstanceFollowRedirects(false);
            connection.setFixedLengthStreamingMode(body.length);
            connection.setRequestProperty("User-Agent", USER_AGENT);
            connection.setRequestProperty("x_bd_data_type", "protobuf");
            connection.setRequestProperty("Accept-Encoding", "identity");
            connection.setRequestProperty("Connection", "keep-alive");
            connection.setRequestProperty("Content-Type",
                    "multipart/form-data; boundary=" + BOUNDARY);
            try (OutputStream output = connection.getOutputStream()) {
                output.write(body);
            }
            requestCount++;
            int status = connection.getResponseCode();
            if (status != HttpURLConnection.HTTP_OK) {
                boolean rate = status == 403 || status == 429;
                throw new CollectException("HTTP " + status, rate, status);
            }
            String contentType = safe(connection.getContentType()).toLowerCase(Locale.ROOT);
            if (contentType.contains("text/html")) {
                throw new CollectException("触发贴吧安全验证", true, 0);
            }
            try (InputStream input = connection.getInputStream()) {
                byte[] data = readLimited(input, 20 * 1024 * 1024);
                if (looksLikeHtml(data)) {
                    throw new CollectException("触发贴吧安全验证", true, 0);
                }
                return data;
            }
        } finally {
            if (connection != null) {
                connection.disconnect();
            }
        }
    }

    private ThreadsPage parseThreads(byte[] response) throws CollectException {
        TiebaProto.Message root = TiebaProto.Message.parse(response);
        checkError(root.message(1));
        TiebaProto.Message data = root.message(2);
        if (data == null) {
            throw new CollectException("贴吧列表响应缺少 data", false, 0);
        }
        long fid = 0;
        TiebaProto.Message forum = data.message(2);
        if (forum != null) {
            fid = forum.varint(1, 0);
        }
        boolean hasMore = false;
        TiebaProto.Message page = data.message(4);
        if (page != null) {
            hasMore = page.varint(6, 0) != 0;
        }
        Map<Long, String> users = parseUsers(data.messages(17));
        List<ThreadSummary> threads = new ArrayList<>();
        for (TiebaProto.Message item : data.messages(7)) {
            long tid = item.varint(1, 0);
            if (tid <= 0) {
                continue;
            }
            long authorId = item.varint(56, 0);
            String author = users.get(authorId);
            if (author == null || author.isEmpty()) {
                author = userDisplay(item.message(18));
            }
            threads.add(new ThreadSummary(tid, item.text(3), author,
                    safeInt(item.varint(45, 0)), safeInt(item.varint(7, 0)),
                    item.varint(9, 0) != 0, item.varint(181, 0) != 0,
                    item.varint(198, 0) != 0));
        }
        return new ThreadsPage(fid, hasMore, threads);
    }

    private PostsPage parsePosts(byte[] response) throws CollectException {
        TiebaProto.Message root = TiebaProto.Message.parse(response);
        checkError(root.message(1));
        TiebaProto.Message data = root.message(2);
        if (data == null) {
            throw new CollectException("楼层响应缺少 data", false, 0);
        }
        boolean hasMore = false;
        TiebaProto.Message page = data.message(3);
        if (page != null) {
            hasMore = page.varint(6, 0) != 0;
        }
        TiebaProto.Message thread = data.message(8);
        String title = thread == null ? "" : thread.text(3);
        String author = thread == null ? "" : userDisplay(thread.message(18));
        int createTime = thread == null ? 0 : safeInt(thread.varint(45, 0));
        int replyNum = thread == null ? 0 : safeInt(thread.varint(4, 0));
        int viewNum = thread == null ? 0 : safeInt(thread.varint(5, 0));
        Map<Long, String> users = parseUsers(data.messages(13));
        List<Floor> floors = new ArrayList<>();
        for (TiebaProto.Message post : data.messages(6)) {
            long pid = post.varint(1, 0);
            long authorId = post.varint(19, 0);
            String floorAuthor = users.get(authorId);
            if (floorAuthor == null || floorAuthor.isEmpty()) {
                floorAuthor = userDisplay(post.message(23));
            }
            int agree = 0;
            TiebaProto.Message agreeNode = post.message(37);
            if (agreeNode != null) {
                agree = safeInt(agreeNode.varint(1, 0));
            }
            String text = assembleContent(post.messages(5));
            floors.add(new Floor(pid, safeInt(post.varint(3, 0)),
                    safeInt(post.varint(4, 0)), agree, floorAuthor, text));
        }
        return new PostsPage(hasMore, title, author, createTime,
                replyNum, viewNum, floors);
    }

    private Map<Long, String> parseUsers(List<TiebaProto.Message> list) {
        Map<Long, String> result = new HashMap<>();
        for (TiebaProto.Message user : list) {
            long id = user.varint(2, 0);
            String display = userDisplay(user);
            if (id != 0 && !display.isEmpty()) {
                result.put(id, display);
            }
        }
        return result;
    }

    private String userDisplay(TiebaProto.Message user) {
        if (user == null) {
            return "";
        }
        String shown = user.text(4);
        return shown.isEmpty() ? user.text(3) : shown;
    }

    private String assembleContent(List<TiebaProto.Message> fragments) {
        StringBuilder builder = new StringBuilder();
        for (TiebaProto.Message fragment : fragments) {
            int type = safeInt(fragment.varint(1, 0));
            String text = fragment.text(2);
            if (type == 0 || type == 1 || type == 2 || type == 4 || type == 9
                    || type == 11 || type == 18 || type == 27 || type == 40) {
                if (type == 1 && text.isEmpty()) {
                    text = fragment.text(3);
                }
                builder.append(text);
            } else if (type == 3 || type == 20) {
                builder.append("[图片]");
            } else if (type == 5) {
                builder.append("[视频]");
            } else if (type == 10) {
                builder.append("[语音]");
            }
        }
        return builder.toString().trim();
    }

    private void checkError(TiebaProto.Message error) throws CollectException {
        if (error == null) {
            return;
        }
        int code = safeInt(error.varint(1, 0));
        if (code != 0) {
            throw new CollectException("贴吧错误 " + code + " " + error.text(2),
                    code >= 110000 && code < 111000, code);
        }
    }

    private void throttle() throws Exception {
        throwIfCanceled();
        if (lastRequestAt > 0) {
            boolean loggedIn = !bduss.isEmpty();
            long minimum = loggedIn
                    ? 1_000L + random.nextInt(1_001)
                    : 1_500L + random.nextInt(1_501);
            long wait = minimum - (System.currentTimeMillis() - lastRequestAt);
            if (wait > 0) {
                sleep(wait);
            }
        }
        String today = new SimpleDateFormat("yyyy-MM-dd", Locale.ROOT)
                .format(new Date());
        String savedDay = preferences.getString("tieba_budget_day", "");
        int used = today.equals(savedDay)
                ? preferences.getInt("tieba_budget_used", 0) : 0;
        int limit = bduss.isEmpty() ? DAILY_BUDGET : DAILY_BUDGET * 2;
        if (used >= limit) {
            throw new BudgetException();
        }
        preferences.edit()
                .putString("tieba_budget_day", today)
                .putInt("tieba_budget_used", used + 1)
                .apply();
        lastRequestAt = System.currentTimeMillis();
        throwIfCanceled();
    }

    private void sleep(long millis) throws Exception {
        long end = System.currentTimeMillis() + millis;
        while (System.currentTimeMillis() < end) {
            throwIfCanceled();
            Thread.sleep(Math.min(200L, end - System.currentTimeMillis()));
        }
    }

    private void throwIfCanceled() throws CanceledException {
        if (canceled || Thread.currentThread().isInterrupted()) {
            throw new CanceledException();
        }
    }

    private void ensureForums() {
        db.execSQL("INSERT OR IGNORE INTO collector_forums(fname,enabled) VALUES(?,1)",
                new Object[]{"yy小说吧"});
        db.execSQL("INSERT OR IGNORE INTO collector_forums(fname,enabled) VALUES(?,1)",
                new Object[]{"哀伤雪刃"});
    }

    private List<ForumState> loadForums() {
        List<ForumState> result = new ArrayList<>();
        try (Cursor cursor = db.rawQuery(
                "SELECT fname,fid,enabled,last_thread_time,last_tid," +
                        "consecutive_failures,cooldown_until,total_threads,total_floors " +
                        "FROM collector_forums ORDER BY rowid", null)) {
            while (cursor.moveToNext()) {
                result.add(new ForumState(
                        safe(cursor.getString(0)), cursor.getLong(1),
                        cursor.getInt(2) != 0, cursor.getLong(3), cursor.getLong(4),
                        cursor.getInt(5), cursor.getLong(6),
                        cursor.getLong(7), cursor.getLong(8)));
            }
        }
        return result;
    }

    private void updateForumFid(String fname, long fid) {
        db.execSQL("UPDATE collector_forums SET fid=? WHERE fname=?",
                new Object[]{fid, fname});
    }

    void commitForumImport(ForumScan scan, int selectedCount, boolean importAll,
                           long targetTime, long targetTid,
                           int addedThreads, int addedFloors, int skipped) {
        if (scan.cooldown) {
            return;
        }
        int failures = 0;
        try (Cursor cursor = db.rawQuery(
                "SELECT consecutive_failures FROM collector_forums WHERE fname=?",
                new String[]{scan.fname})) {
            if (cursor.moveToFirst()) {
                failures = cursor.getInt(0);
            }
        }
        boolean hasError = !scan.error.isEmpty();
        if (hasError) {
            failures++;
        } else {
            failures = 0;
        }
        boolean cooldown = failures >= FORUM_FAILURE_LIMIT;
        long cooldownUntil = cooldown
                ? System.currentTimeMillis() + COOLDOWN_MS : 0;
        boolean advance = importAll && scan.complete && !hasError;
        String status;
        if (hasError) {
            status = "api_error";
        } else if (advance) {
            status = "ok";
        } else if (selectedCount == 0) {
            status = "skipped";
        } else {
            status = "partial";
        }
        db.execSQL("UPDATE collector_forums SET " +
                        "last_thread_time=CASE WHEN ? THEN ? ELSE last_thread_time END," +
                        "last_tid=CASE WHEN ? THEN ? ELSE last_tid END," +
                        "last_run_at=?,last_status=?,last_error=?," +
                        "consecutive_failures=?,cooldown_until=?," +
                        "total_threads=total_threads+?,total_floors=total_floors+? " +
                        "WHERE fname=?",
                new Object[]{advance ? 1 : 0, targetTime,
                        advance ? 1 : 0, targetTid, nowIso(), status,
                        hasError ? scan.error : "", failures,
                        cooldownUntil, addedThreads, addedFloors, scan.fname});
        String detail = "选择=" + selectedCount +
                " 新增=" + addedThreads + " 楼层=" + addedFloors +
                " 跳过=" + skipped +
                (advance ? " 水位=" + formatTime(targetTime) +
                        " tid=" + targetTid : " 水位未推进") +
                (hasError ? " err=" + scan.error : "");
        db.execSQL("INSERT INTO collector_logs(" +
                        "fname,run_at,status,threads_added,floors_added,skipped_dup,detail) " +
                        "VALUES(?,?,?,?,?,?,?)",
                new Object[]{scan.fname, nowIso(), status, addedThreads,
                        addedFloors, skipped, detail});
        db.execSQL("DELETE FROM collector_logs WHERE id NOT IN " +
                "(SELECT id FROM collector_logs ORDER BY id DESC LIMIT 200)");
        log(scan.fname, hasError ? "失败" : "导入", detail);
    }

    private void log(String fname, String event, String detail) {
        listener.onLog(fname, event, detail);
    }

    private static byte[] readLimited(InputStream input, int max)
            throws Exception {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        byte[] buffer = new byte[64 * 1024];
        int total = 0;
        int count;
        while ((count = input.read(buffer)) != -1) {
            total += count;
            if (total > max) {
                throw new IllegalStateException("贴吧响应过大");
            }
            output.write(buffer, 0, count);
        }
        return output.toByteArray();
    }

    private static boolean looksLikeHtml(byte[] data) {
        if (data == null || data.length == 0) {
            return false;
        }
        String probe = new String(data, 0, Math.min(data.length, 1024),
                StandardCharsets.UTF_8).toLowerCase(Locale.ROOT);
        return probe.contains("<!doctype") || probe.contains("<html")
                || probe.contains("wappass") || probe.contains("安全验证")
                || probe.contains("验证码");
    }

    private static String nowIso() {
        SimpleDateFormat format = new SimpleDateFormat(
                "yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.ROOT);
        format.setTimeZone(TimeZone.getTimeZone("UTC"));
        return format.format(new Date());
    }

    private static String formatTime(long epochMillisOrSeconds) {
        if (epochMillisOrSeconds <= 0) {
            return "冷启动";
        }
        long millis = epochMillisOrSeconds < 10_000_000_000L
                ? epochMillisOrSeconds * 1000L : epochMillisOrSeconds;
        SimpleDateFormat format = new SimpleDateFormat(
                "MM-dd HH:mm", Locale.CHINA);
        format.setTimeZone(TimeZone.getTimeZone("Asia/Shanghai"));
        return format.format(new Date(millis));
    }

    private static int safeInt(long value) {
        return value > Integer.MAX_VALUE ? Integer.MAX_VALUE : (int) value;
    }

    private static int clamp(int value, int minimum, int maximum) {
        return Math.max(minimum, Math.min(maximum, value));
    }

    private static String safe(String value) {
        return value == null ? "" : value;
    }

    private static String readable(Exception error) {
        String message = error.getMessage();
        return message == null || message.trim().isEmpty()
                ? error.getClass().getSimpleName() : message;
    }
}
