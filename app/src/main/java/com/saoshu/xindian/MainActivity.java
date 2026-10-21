package com.saoshu.xindian;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.res.ColorStateList;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.graphics.drawable.StateListDrawable;
import android.graphics.text.LineBreaker;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.Editable;
import android.text.TextWatcher;
import android.text.SpannableStringBuilder;
import android.text.style.StyleSpan;
import android.text.Layout;
import android.text.style.ForegroundColorSpan;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewConfiguration;
import android.view.Window;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputMethodManager;
import android.widget.AbsListView;
import android.widget.AdapterView;
import android.widget.BaseAdapter;
import android.widget.Button;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.ListView;
import android.widget.ProgressBar;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.io.OutputStreamWriter;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.text.Normalizer;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.TimeZone;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class MainActivity extends Activity {
    private static final int DB_VERSION = 6;
    private static final int REQUEST_EXPORT_DATA = 2201;
    private static final int REQUEST_IMPORT_DATA = 2202;
    private static final int REQUEST_EXPORT_SINGLE = 2203;
    private static final int REQUEST_EXPORT_USER_BACKUP = 2204;
    private static final int REQUEST_IMPORT_USER_BACKUP = 2205;
    private int TEAL;
    private int TEAL_DARK;
    private int TEAL_DEEP;
    private int TEAL_PALE;
    private int TEAL_SOFT;
    // Legacy names are retained to keep the view code compact; the whole UI is
    // now one teal family, with gold reserved for a few reading accents.
    private int PINK;
    private int PINK_DARK;
    private int PINK_PALE;
    private static final int GOLD = Color.rgb(244, 195, 0);
    private static final int BG = Color.rgb(245, 247, 246);
    private static final int CARD = Color.WHITE;
    private static final int TEXT = Color.rgb(38, 50, 56);
    private static final int MUTED = Color.rgb(111, 121, 119);
    private static final int LINE = Color.rgb(225, 232, 230);
    private static final String PREFS = "saoshu_prefs";

    private final ExecutorService executor = Executors.newFixedThreadPool(3);
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final AtomicInteger searchVersion = new AtomicInteger();
    private SQLiteDatabase db;
    private SharedPreferences preferences;
    private FrameLayout content;
    private FrameLayout bottomBar;
    private final LinearLayout[] navItems = new LinearLayout[5];
    private int currentTab = 0;
    private int detailBackTab = 0;
    private boolean detailOpen = false;
    private long currentDetailId = -1;
    private long pendingSingleExportId = -1;

    private String searchQuery = "";
    private String searchCategory = "";
    private String searchSource = "";
    private boolean searchFullText = false;
    private EditText searchField;
    private TextView searchStatus;
    private ListView searchList;
    private Runnable pendingSearch;

    private EditText bookField;
    private ListView bookList;
    private BookAdapter bookAdapter;
    private final List<Book> books = new ArrayList<>();
    private int bookOffset = 0;
    private boolean booksLoading = false;
    private boolean booksEnded = false;
    private String bookQuery = "";
    private boolean dataBusy = false;
    private TextView dataStatus;

    private static final Pattern QUERY_CHUNKS =
            Pattern.compile("[a-z0-9]+|[\\u4e00-\\u9fff]+", Pattern.CASE_INSENSITIVE);

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        preferences = getSharedPreferences(PREFS, MODE_PRIVATE);
        applySelectedTheme();
        configureWindow();
        showLoadingScreen();
        executor.execute(this::prepareDatabase);
    }

    private void configureWindow() {
        Window window = getWindow();
        window.setStatusBarColor(TEAL_DEEP);
        window.setNavigationBarColor(PINK_DARK);
        if (android.os.Build.VERSION.SDK_INT >= 26) {
            window.getDecorView().setSystemUiVisibility(0);
        }
    }

    private void applySelectedTheme() {
        String themeId = preferences.getString("theme_id", "teal");
        int[] palette = themePalette(themeId);
        TEAL = palette[0];
        TEAL_DARK = palette[1];
        TEAL_DEEP = palette[2];
        TEAL_PALE = palette[3];
        TEAL_SOFT = palette[4];
        PINK = TEAL;
        PINK_DARK = TEAL_DEEP;
        PINK_PALE = TEAL_PALE;
    }

    private int[] themePalette(String themeId) {
        if ("ocean".equals(themeId)) {
            return new int[]{
                    Color.rgb(30, 136, 229),
                    Color.rgb(21, 101, 192),
                    Color.rgb(13, 60, 104),
                    Color.rgb(227, 242, 253),
                    Color.rgb(245, 250, 255)
            };
        }
        if ("amber".equals(themeId)) {
            return new int[]{
                    Color.rgb(166, 106, 46),
                    Color.rgb(122, 74, 29),
                    Color.rgb(74, 43, 18),
                    Color.rgb(247, 235, 221),
                    Color.rgb(252, 248, 242)
            };
        }
        if ("rose".equals(themeId)) {
            return new int[]{
                    Color.rgb(199, 91, 122),
                    Color.rgb(156, 62, 91),
                    Color.rgb(97, 38, 58),
                    Color.rgb(252, 233, 239),
                    Color.rgb(255, 247, 249)
            };
        }
        if ("violet".equals(themeId)) {
            return new int[]{
                    Color.rgb(126, 87, 194),
                    Color.rgb(94, 53, 177),
                    Color.rgb(46, 26, 71),
                    Color.rgb(238, 232, 247),
                    Color.rgb(249, 247, 252)
            };
        }
        return new int[]{
                Color.rgb(0, 150, 136),
                Color.rgb(0, 105, 96),
                Color.rgb(0, 77, 76),
                Color.rgb(224, 242, 241),
                Color.rgb(242, 249, 248)
        };
    }

    private void showLoadingScreen() {
        LinearLayout loading = new LinearLayout(this);
        loading.setOrientation(LinearLayout.VERTICAL);
        loading.setGravity(Gravity.CENTER);
        loading.setPadding(dp(28), dp(28), dp(28), dp(28));
        loading.setBackgroundColor(TEAL);

        TextView mark = text("典", 42, Color.WHITE, Typeface.BOLD);
        mark.setGravity(Gravity.CENTER);
        mark.setBackground(round(Color.argb(35, 255, 255, 255), 22));
        LinearLayout.LayoutParams markParams = new LinearLayout.LayoutParams(dp(88), dp(88));
        loading.addView(mark, markParams);

        TextView title = text("扫书新典", 29, Color.WHITE, Typeface.BOLD);
        title.setGravity(Gravity.CENTER);
        addWithTop(loading, title, 22);

        TextView subtitle = text("离线扫书资料库", 15, Color.argb(220, 255, 255, 255), Typeface.NORMAL);
        subtitle.setGravity(Gravity.CENTER);
        addWithTop(loading, subtitle, 8);

        ProgressBar progress = new ProgressBar(this);
        progress.setIndeterminate(true);
        LinearLayout.LayoutParams pp = new LinearLayout.LayoutParams(dp(42), dp(42));
        pp.topMargin = dp(34);
        loading.addView(progress, pp);

        TextView status = text("正在准备离线资料库…", 13, Color.argb(220, 255, 255, 255), Typeface.NORMAL);
        status.setGravity(Gravity.CENTER);
        status.setTag("loading_status");
        addWithTop(loading, status, 18);
        setContentView(loading);
    }

    private void prepareDatabase() {
        try {
            File target = new File(getFilesDir(), "saoshu.db");
            int installedVersion = preferences.getInt("db_asset_version", -1);
            boolean available = target.isFile() && target.length() > 65_536L;
            File legacy = new File(getFilesDir(), "saoshu.pre-v6.db");
            if (!available || installedVersion != DB_VERSION) {
                if (target.isFile() && target.length() > 1_000_000L) {
                    copyFile(target, legacy);
                }
                copyDatabase(target);
            }
            db = SQLiteDatabase.openDatabase(
                    target.getAbsolutePath(), null, SQLiteDatabase.OPEN_READWRITE);
            initializeLocalSchema();
            if (legacy.isFile()) {
                migrateLegacyDatabase(legacy);
                if (!legacy.delete()) {
                    legacy.deleteOnExit();
                }
            }
            preferences.edit().putInt("db_asset_version", DB_VERSION).apply();
            mainHandler.post(this::showMainShell);
        } catch (Exception error) {
            mainHandler.post(() -> showFatalError(error));
        }
    }

    private void initializeLocalSchema() {
        db.execSQL("CREATE TABLE IF NOT EXISTS local_deleted (" +
                "document_id INTEGER PRIMARY KEY," +
                "deleted_at TEXT NOT NULL)");
        Cursor cursor = db.rawQuery("SELECT 1 FROM sqlite_master " +
                "WHERE type='table' AND name='search_idx' LIMIT 1", null);
        boolean hasSearchIndex;
        try {
            hasSearchIndex = cursor.moveToFirst();
        } finally {
            cursor.close();
        }
        if (!hasSearchIndex) {
            buildLocalSearchIndex();
        }
    }

    private void buildLocalSearchIndex() {
        mainHandler.post(() -> updateLoadingStatus("正在生成本地搜索索引…"));
        Cursor cursor = db.rawQuery(
                "SELECT id,title,author,mentioned_books_json FROM documents", null);
        int total = Math.max(1, (int) localDocumentCount());
        int done = 0;
        db.beginTransaction();
        try {
            db.execSQL("CREATE VIRTUAL TABLE search_idx USING fts4(" +
                    "tokens, tokenize=simple)");
            while (cursor.moveToNext()) {
                long id = cursor.getLong(0);
                String title = safe(cursor.getString(1));
                String author = safe(cursor.getString(2));
                String mentioned = safe(cursor.getString(3));
                StringBuilder searchable = new StringBuilder(title).append(' ')
                        .append(author);
                try {
                    JSONArray books = new JSONArray(mentioned);
                    for (int i = 0; i < books.length(); i++) {
                        searchable.append(' ').append(books.optString(i, ""));
                    }
                } catch (Exception ignored) {
                }
                db.execSQL("INSERT INTO search_idx(rowid,tokens) VALUES(?,?)",
                        new Object[]{id, buildFtsQuery(searchable.toString())});
                done++;
                if (done % 2000 == 0) {
                    final int percent = (int) Math.min(99, done * 100L / total);
                    mainHandler.post(() -> updateLoadingStatus(
                            "正在生成本地搜索索引 " + percent + "%"));
                    db.yieldIfContendedSafely();
                }
            }
            db.setTransactionSuccessful();
        } finally {
            cursor.close();
            db.endTransaction();
        }
    }

    private void copyDatabase(File target) throws Exception {
        File temporary = new File(getFilesDir(), "saoshu.db.installing");
        if (temporary.exists() && !temporary.delete()) {
            throw new IllegalStateException("无法清理上次未完成的数据库文件");
        }
        InputStream input = getAssets().open("saoshu.db");
        long expectedBytes = Math.max(1, input.available());
        FileOutputStream output = new FileOutputStream(temporary);
        byte[] buffer = new byte[1024 * 1024];
        long copied = 0;
        int nextReport = 5;
        try {
            int count;
            while ((count = input.read(buffer)) != -1) {
                output.write(buffer, 0, count);
                copied += count;
                int percent = (int) Math.min(99, copied * 100L / expectedBytes);
                if (percent >= nextReport) {
                    final int shown = percent;
                    mainHandler.post(() -> updateLoadingStatus("正在解包资料库 " + shown + "%"));
                    nextReport += 5;
                }
            }
            output.flush();
            output.getFD().sync();
        } finally {
            try {
                output.close();
            } finally {
                input.close();
            }
        }
        if (target.exists() && !target.delete()) {
            throw new IllegalStateException("无法替换旧数据库");
        }
        if (!temporary.renameTo(target)) {
            throw new IllegalStateException("数据库安装失败");
        }
        mainHandler.post(() -> updateLoadingStatus("正在校验资料库…"));
    }

    private void copyFile(File source, File destination) throws Exception {
        if (destination.exists() && !destination.delete()) {
            throw new IllegalStateException("无法清理旧版数据库备份");
        }
        try (FileInputStream input = new FileInputStream(source);
             FileOutputStream output = new FileOutputStream(destination)) {
            byte[] buffer = new byte[1024 * 1024];
            int count;
            while ((count = input.read(buffer)) != -1) {
                output.write(buffer, 0, count);
            }
            output.getFD().sync();
        }
    }

    private void migrateLegacyDatabase(File legacyFile) {
        db.execSQL("ATTACH DATABASE ? AS legacy", new Object[]{legacyFile.getAbsolutePath()});
        db.beginTransaction();
        try {
            Cursor missing = db.rawQuery(
                    "SELECT d.* FROM legacy.documents d WHERE NOT EXISTS " +
                            "(SELECT 1 FROM main.documents m " +
                            "WHERE m.canonical_key=d.canonical_key)",
                    null);
            try {
                while (missing.moveToNext()) {
                    Document document = Document.fromCursor(missing);
                    String key = safe(missing.getString(
                            missing.getColumnIndexOrThrow("canonical_key")));
                    db.execSQL("INSERT INTO main.documents(" +
                                    "canonical_key,title,title_norm,author,author_norm," +
                                    "content,category,source_type,forum,mname,zname," +
                                    "published_at,source_url,word,hot_score," +
                                    "mentioned_books_json) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                            new Object[]{key, document.title, compact(document.title),
                                    document.author, compact(document.author), document.content,
                                    document.category, document.sourceType, document.forum,
                                    safe(missing.getString(missing.getColumnIndexOrThrow("mname"))),
                                    safe(missing.getString(missing.getColumnIndexOrThrow("zname"))),
                                    document.date, document.sourceUrl, document.word,
                                    missing.getLong(missing.getColumnIndexOrThrow("hot_score")),
                                    document.mentionedJson});
                    long id = db.compileStatement("SELECT last_insert_rowid()")
                            .simpleQueryForLong();
                    indexDocumentSearch(id, document.title, document.author,
                            document.mentionedJson);
                    adjustBookIndex(document.title, document.mentionedJson,
                            document.sourceType, document.date, id, document.word, 1);
                }
            } finally {
                missing.close();
            }

            db.execSQL("INSERT INTO main.document_sources(" +
                    "document_id,source_kind,source_ref,source_url) " +
                    "SELECT m.id,s.source_kind,s.source_ref,s.source_url " +
                    "FROM legacy.document_sources s " +
                    "JOIN legacy.documents d ON d.id=s.document_id " +
                    "JOIN main.documents m ON m.canonical_key=d.canonical_key " +
                    "WHERE NOT EXISTS (SELECT 1 FROM main.document_sources x " +
                    "WHERE x.document_id=m.id AND x.source_kind=s.source_kind " +
                    "AND x.source_ref=s.source_ref " +
                    "AND coalesce(x.source_url,'')=coalesce(s.source_url,''))");

            Cursor hasDeleted = db.rawQuery("SELECT 1 FROM legacy.sqlite_master " +
                    "WHERE type='table' AND name='local_deleted' LIMIT 1", null);
            boolean legacyHasDeleted;
            try {
                legacyHasDeleted = hasDeleted.moveToFirst();
            } finally {
                hasDeleted.close();
            }
            if (legacyHasDeleted) {
                db.execSQL("INSERT OR IGNORE INTO main.local_deleted(document_id,deleted_at) " +
                        "SELECT m.id,l.deleted_at FROM legacy.local_deleted l " +
                        "JOIN legacy.documents d ON d.id=l.document_id " +
                        "JOIN main.documents m ON m.canonical_key=d.canonical_key");
            }
            db.setTransactionSuccessful();
        } finally {
            db.endTransaction();
            db.execSQL("DETACH DATABASE legacy");
        }
    }

    private void updateLoadingStatus(String message) {
        View root = findViewById(android.R.id.content);
        if (root instanceof ViewGroup && ((ViewGroup) root).getChildCount() > 0) {
            View first = ((ViewGroup) root).getChildAt(0);
            if (first instanceof ViewGroup) {
                View tagged = first.findViewWithTag("loading_status");
                if (tagged instanceof TextView) {
                    ((TextView) tagged).setText(message);
                }
            }
        }
    }

    private void showFatalError(Exception error) {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setGravity(Gravity.CENTER);
        box.setPadding(dp(28), dp(28), dp(28), dp(28));
        box.setBackgroundColor(BG);
        TextView title = text("资料库加载失败", 22, TEXT, Typeface.BOLD);
        title.setGravity(Gravity.CENTER);
        box.addView(title);
        TextView detail = text(error.getMessage() == null ? error.toString() : error.getMessage(),
                14, MUTED, Typeface.NORMAL);
        detail.setGravity(Gravity.CENTER);
        detail.setPadding(0, dp(12), 0, dp(20));
        box.addView(detail);
        Button retry = new Button(this);
        retry.setText("重新尝试");
        retry.setOnClickListener(v -> {
            showLoadingScreen();
            executor.execute(this::prepareDatabase);
        });
        box.addView(retry);
        setContentView(box);
    }

    private void showMainShell() {
        try {
            if (db == null || !db.isOpen()) {
                throw new IllegalStateException("数据库未打开");
            }
            FrameLayout root = new FrameLayout(this);
            root.setBackgroundColor(BG);

            content = new FrameLayout(this);
            content.setBackgroundColor(BG);
            root.addView(content, new FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT));

            bottomBar = buildBottomBar();
            bottomBar.setElevation(dp(12));
            FrameLayout.LayoutParams bottomParams = new FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, dp(52), Gravity.BOTTOM);
            bottomParams.setMargins(dp(12), 0, dp(12), dp(8));
            root.addView(bottomBar, bottomParams);
            setContentView(root);
            switchTab(0);
        } catch (Exception error) {
            showFatalError(error);
        }
    }

    private FrameLayout buildBottomBar() {
        FrameLayout shell = new FrameLayout(this);
        shell.setBackground(round((PINK_DARK & 0x00ffffff) | 0xf0000000, 20));
        shell.setClipToOutline(true);
        shell.setElevation(dp(10));

        LinearLayout bar = new LinearLayout(this);
        bar.setOrientation(LinearLayout.HORIZONTAL);
        bar.setGravity(Gravity.CENTER_VERTICAL);
        bar.setPadding(dp(5), dp(2), dp(5), dp(2));
        String[] icons = {"⌂", "⌕", "▤", "★", "⇅"};
        String[] labels = {"首页", "搜索", "书库", "收藏", "数据"};
        for (int i = 0; i < 5; i++) {
            final int tab = i;
            NavTabView item = new NavTabView(this);
            item.setGravity(Gravity.CENTER);
            item.setContentDescription(labels[i]);
            item.setClickable(true);
            item.setFocusable(true);
            item.setOnClickListener(v -> switchTab(tab));
            TextView icon = text(icons[i], 18, Color.WHITE, Typeface.BOLD);
            icon.setGravity(Gravity.CENTER);
            icon.setTag("nav_icon");
            icon.setClickable(false);
            item.addView(icon, new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, dp(42)));
            navItems[i] = item;
            LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                    0, ViewGroup.LayoutParams.MATCH_PARENT, 1f);
            params.setMargins(dp(3), 0, dp(3), 0);
            bar.addView(item, params);
        }
        shell.addView(bar, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT));
        return shell;
    }

    private void switchTab(int tab) {
        currentTab = tab;
        detailOpen = false;
        if (bottomBar != null) {
            bottomBar.setVisibility(View.VISIBLE);
        }
        for (int i = 0; i < navItems.length; i++) {
            if (navItems[i] == null) {
                continue;
            }
            int color = i == tab ? Color.WHITE : Color.argb(178, 255, 255, 255);
            View icon = navItems[i].findViewWithTag("nav_icon");
            if (icon instanceof TextView) {
                ((TextView) icon).setTextColor(color);
            }
            navItems[i].setBackground(rippleRound(
                    i == tab ? Color.argb(34, 255, 255, 255) : Color.TRANSPARENT,
                    Color.TRANSPARENT, 17, Color.argb(55, 255, 255, 255)));
        }
        content.removeAllViews();
        if (tab == 0) {
            content.addView(buildHome());
        } else if (tab == 1) {
            content.addView(buildSearch());
        } else if (tab == 2) {
            content.addView(buildBooks());
        } else if (tab == 3) {
            content.addView(buildFavorites());
        } else {
            content.addView(buildDataManager());
        }
    }

    private View buildHome() {
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        LinearLayout page = column();
        page.setPadding(dp(16), dp(16), dp(16), dp(74));
        scroll.addView(page, new ScrollView.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        LinearLayout hero = column();
        hero.setPadding(dp(20), dp(20), dp(20), dp(18));
        hero.setBackground(gradient(TEAL_DARK, TEAL, 20));
        LinearLayout brandRow = row();
        TextView brand = text("扫书新典", 28, Color.WHITE, Typeface.BOLD);
        brandRow.addView(brand, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        TextView edition = text("离线版  v2.7", 12, Color.WHITE, Typeface.BOLD);
        edition.setGravity(Gravity.CENTER);
        edition.setPadding(dp(10), dp(5), dp(10), dp(5));
        edition.setBackground(round(Color.argb(35, 255, 255, 255), 12));
        brandRow.addView(edition);
        hero.addView(brandRow);

        TextView subtitle = text("把散落在贴吧与资料库里的扫书评论，收进一本随身书。",
                14, Color.argb(225, 255, 255, 255), Typeface.NORMAL);
        subtitle.setLineSpacing(0, 1.25f);
        addWithTop(hero, subtitle, 7);

        LinearLayout stats = row();
        stats.setPadding(0, dp(18), 0, 0);
        long docs = localDocumentCount();
        long booksCount = localBookCount();
        long sourceRows = visibleSourceCount();
        stats.addView(statBox(formatCompact(docs), "条内容"),
                new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        stats.addView(statBox(formatCompact(booksCount), "本书名"),
                new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        stats.addView(statBox(formatCompact(sourceRows), "次来源"),
                new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        hero.addView(stats);
        page.addView(hero);

        LinearLayout searchCard = row();
        searchCard.setGravity(Gravity.CENTER_VERTICAL);
        searchCard.setPadding(dp(17), dp(14), dp(13), dp(14));
        searchCard.setBackground(rippleRound(PINK, Color.TRANSPARENT, 15,
                Color.argb(60, 255, 255, 255)));
        searchCard.setElevation(dp(3));
        TextView searchIcon = text("⌕", 25, Color.WHITE, Typeface.BOLD);
        searchCard.addView(searchIcon);
        TextView searchPrompt = text("搜索书名、作者或正文关键词", 15,
                Color.WHITE, Typeface.NORMAL);
        searchPrompt.setPadding(dp(10), 0, 0, 0);
        searchCard.addView(searchPrompt, new LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        TextView go = text("进入 ›", 13, PINK_DARK, Typeface.BOLD);
        go.setPadding(dp(10), dp(6), dp(10), dp(6));
        go.setBackground(round(Color.WHITE, 12));
        searchCard.addView(go);
        searchCard.setOnClickListener(v -> switchTab(1));
        addWithTop(page, searchCard, 14);

        page.addView(sectionTitle("按类型浏览", "全部搜索", v -> switchTab(1)));

        HorizontalScrollView categoriesScroll = new HorizontalScrollView(this);
        categoriesScroll.setHorizontalScrollBarEnabled(false);
        LinearLayout categoryRow = row();
        Cursor categories = db.rawQuery(
                "SELECT name,count FROM categories ORDER BY count DESC", null);
        try {
            while (categories.moveToNext()) {
                String name = safe(categories.getString(0));
                long count = categories.getLong(1);
                TextView chip = text(name + "  " + formatCompact(count), 13,
                        categoryTextColor(name), Typeface.BOLD);
                chip.setGravity(Gravity.CENTER);
                chip.setPadding(dp(15), dp(9), dp(15), dp(9));
                chip.setBackground(rippleRound(categoryPaleColor(name),
                        Color.TRANSPARENT, 18, Color.argb(45, 0, 0, 0)));
                chip.setOnClickListener(v -> {
                    searchQuery = "";
                    searchCategory = name;
                    searchSource = "";
                    searchFullText = false;
                    switchTab(1);
                });
                LinearLayout.LayoutParams cp = new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
                cp.rightMargin = dp(8);
                categoryRow.addView(chip, cp);
            }
        } finally {
            categories.close();
        }
        categoriesScroll.addView(categoryRow);
        page.addView(categoriesScroll);

        page.addView(sectionTitle("最近收录", "最近 8 条", v -> {
            searchCategory = "";
            switchTab(1);
        }));
        List<Document> recent = queryDocuments(
                "SELECT d.* FROM documents d WHERE d.published_at<>'' " +
                        "AND d.id NOT IN (SELECT document_id FROM local_deleted) " +
                        "ORDER BY d.published_at DESC,d.id DESC LIMIT 8", new String[]{});
        for (Document document : recent) {
            addWithTop(page, documentCard(document, 100, false), 10);
        }

        LinearLayout note = column();
        note.setPadding(dp(15), dp(14), dp(15), dp(14));
        note.setBackground(round(TEAL_SOFT, 14));
        TextView noteTitle = text("本地资料库 · 数据截止 2026-10-20", 13, TEAL_DARK, Typeface.BOLD);
        note.addView(noteTitle);
        TextView noteBody = text(
                "资料可在“数据”页导出为本地备份，也可以随时删除或恢复。原帖链接只用于追溯来源。",
                12, MUTED, Typeface.NORMAL);
        noteBody.setLineSpacing(0, 1.35f);
        addWithTop(note, noteBody, 6);
        addWithTop(page, note, 16);
        return scroll;
    }

    private View statBox(String value, String label) {
        LinearLayout box = column();
        box.setGravity(Gravity.CENTER_HORIZONTAL);
        TextView number = text(value, 20, Color.WHITE, Typeface.BOLD);
        number.setGravity(Gravity.CENTER);
        box.addView(number);
        TextView caption = text(label, 12, Color.argb(215, 255, 255, 255), Typeface.NORMAL);
        caption.setGravity(Gravity.CENTER);
        box.addView(caption);
        return box;
    }

    private View buildSearch() {
        LinearLayout page = column();
        page.setBackgroundColor(BG);

        LinearLayout header = column();
        header.setPadding(dp(16), dp(14), dp(16), dp(13));
        header.setBackground(gradient(PINK_DARK, PINK, 0));
        TextView title = text("全库搜索", 23, Color.WHITE, Typeface.BOLD);
        header.addView(title);
        TextView hint = text("标题、作者、书名聚合与正文都可查", 12,
                Color.argb(225, 255, 255, 255), Typeface.NORMAL);
        addWithTop(header, hint, 3);

        LinearLayout inputRow = row();
        inputRow.setGravity(Gravity.CENTER_VERTICAL);
        inputRow.setPadding(dp(12), 0, dp(8), 0);
        inputRow.setBackground(round(Color.WHITE, 13));
        searchField = new EditText(this);
        searchField.setSingleLine(true);
        searchField.setText(searchQuery);
        searchField.setTextSize(15);
        searchField.setTextColor(TEXT);
        searchField.setHintTextColor(Color.rgb(150, 155, 154));
        searchField.setHint("例如：世子很凶 / 作者名 / 西幻");
        searchField.setBackgroundColor(Color.TRANSPARENT);
        searchField.setPadding(0, 0, 0, 0);
        searchField.setImeOptions(EditorInfo.IME_ACTION_SEARCH);
        inputRow.addView(searchField, new LinearLayout.LayoutParams(
                0, dp(51), 1f));
        TextView searchButton = text("搜索", 14, Color.WHITE, Typeface.BOLD);
        searchButton.setGravity(Gravity.CENTER);
        searchButton.setBackground(rippleRound(TEAL, Color.TRANSPARENT, 11,
                Color.argb(55, 255, 255, 255)));
        searchButton.setPadding(dp(17), dp(9), dp(17), dp(9));
        inputRow.addView(searchButton);
        addWithTop(header, inputRow, 13);

        LinearLayout categoryChoices = choiceRow(
                new String[]{"全部类型", "扫书", "推书", "排雷", "讨论", "求书"},
                searchCategory.isEmpty() ? "全部类型" : searchCategory,
                value -> searchCategory = value.equals("全部类型") ? "" : value);
        addWithTop(header, categoryChoices, 11);
        LinearLayout sourceChoices = choiceRow(
                new String[]{"全部来源", "百度贴吧", "雪群推书", "资料库",
                        "文本页面", "丫丫书屋", "剪贴板"},
                searchSource.isEmpty() ? "全部来源" : searchSource,
                value -> searchSource = value.equals("全部来源") ? "" : value);
        addWithTop(header, sourceChoices, 7);
        page.addView(header);

        LinearLayout resultHeader = row();
        resultHeader.setGravity(Gravity.CENTER_VERTICAL);
        resultHeader.setPadding(dp(17), dp(11), dp(10), dp(5));
        searchStatus = text("最近收录的内容", 13, MUTED, Typeface.BOLD);
        resultHeader.addView(searchStatus, new LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        TextView toggle = new FeedbackTextView(this);
        toggle.setText(searchFullText ? "● 全文" : "○ 标题");
        toggle.setTextSize(12);
        toggle.setGravity(Gravity.CENTER);
        toggle.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        toggle.setTextColor(searchFullText ? Color.WHITE : TEAL_DARK);
        toggle.setPadding(dp(11), dp(6), dp(11), dp(6));
        toggle.setBackground(rippleRound(searchFullText ? TEAL : TEAL_PALE,
                Color.TRANSPARENT, 12, Color.argb(48, 0, 0, 0)));
        resultHeader.addView(toggle);
        page.addView(resultHeader);

        searchList = new ListView(this);
        configureListFeedback(searchList);
        searchList.setDivider(null);
        searchList.setDividerHeight(0);
        searchList.setClipToPadding(false);
        searchList.setPadding(dp(10), dp(4), dp(10), dp(64));
        searchList.setBackgroundColor(BG);
        page.addView(searchList, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        searchButton.setOnClickListener(v -> launchSearch());
        toggle.setOnClickListener(v -> {
            searchFullText = !searchFullText;
            toggle.setText(searchFullText ? "● 全文" : "○ 标题");
            toggle.setTextColor(searchFullText ? Color.WHITE : TEAL_DARK);
            toggle.setBackground(rippleRound(searchFullText ? TEAL : TEAL_PALE,
                    Color.TRANSPARENT, 12, Color.argb(48, 0, 0, 0)));
            launchSearch();
        });
        searchField.setOnEditorActionListener((v, actionId, event) -> {
            if (actionId == EditorInfo.IME_ACTION_SEARCH) {
                launchSearch();
                hideKeyboard();
                return true;
            }
            return false;
        });
        searchField.addTextChangedListener(new TextWatcher() {
            @Override
            public void beforeTextChanged(CharSequence s, int start, int count, int after) {
            }

            @Override
            public void onTextChanged(CharSequence s, int start, int before, int count) {
                searchQuery = s.toString();
                if (pendingSearch != null) {
                    mainHandler.removeCallbacks(pendingSearch);
                }
                pendingSearch = () -> launchSearch();
                mainHandler.postDelayed(pendingSearch, 500);
            }

            @Override
            public void afterTextChanged(Editable s) {
            }
        });
        mainHandler.post(this::launchSearch);
        return page;
    }

    private LinearLayout choiceRow(String[] options, String selected, ChoiceListener listener) {
        HorizontalScrollView scroll = new HorizontalScrollView(this);
        scroll.setHorizontalScrollBarEnabled(false);
        LinearLayout row = row();
        final String[] active = {selected};
        for (String option : options) {
            TextView chip = text(option, 12, option.equals(active[0]) ? Color.WHITE : PINK_DARK,
                    Typeface.BOLD);
            chip.setGravity(Gravity.CENTER);
            chip.setPadding(dp(11), dp(6), dp(11), dp(6));
            chip.setBackground(rippleRound(option.equals(active[0])
                            ? PINK_DARK : Color.argb(210, 255, 255, 255),
                    Color.TRANSPARENT, 12, Color.argb(48, 0, 0, 0)));
            chip.setOnClickListener(v -> {
                active[0] = option;
                for (int i = 0; i < row.getChildCount(); i++) {
                    TextView child = (TextView) row.getChildAt(i);
                    boolean isActive = child.getText().toString().equals(active[0]);
                    child.setTextColor(isActive ? Color.WHITE : PINK_DARK);
                    child.setBackground(rippleRound(isActive
                                    ? PINK_DARK : Color.argb(210, 255, 255, 255),
                            Color.TRANSPARENT, 12, Color.argb(48, 0, 0, 0)));
                }
                listener.onSelected(option);
                launchSearch();
            });
            LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            params.rightMargin = dp(6);
            row.addView(chip, params);
        }
        scroll.addView(row);
        return wrapHorizontal(scroll);
    }

    private LinearLayout wrapHorizontal(View child) {
        LinearLayout wrapper = new LinearLayout(this);
        wrapper.setOrientation(LinearLayout.HORIZONTAL);
        wrapper.addView(child, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        return wrapper;
    }

    private void launchSearch() {
        if (searchField == null || searchList == null || searchStatus == null) {
            return;
        }
        searchQuery = searchField.getText().toString().trim();
        final int version = searchVersion.incrementAndGet();
        final String query = searchQuery;
        final String category = searchCategory;
        final String source = searchSource;
        final boolean fullText = searchFullText;
        searchStatus.setText("搜索中…");
        executor.execute(() -> {
            try {
                List<Document> results = searchDocuments(query, category, source, fullText);
                mainHandler.post(() -> {
                    if (version != searchVersion.get() || searchList == null) {
                        return;
                    }
                    searchStatus.setText(query.isEmpty()
                            ? formatCompact(results.size()) + " 条最近内容"
                            : "找到 " + formatCompact(results.size()) + " 条" +
                            (results.size() >= 250 ? "（显示前 250 条）" : ""));
                    searchList.setAdapter(new DocumentAdapter(results, query));
                    if (results.isEmpty()) {
                        searchStatus.setText("没有匹配内容，试试减少关键词或切换全文");
                    }
                });
            } catch (Exception error) {
                mainHandler.post(() -> {
                    if (version == searchVersion.get()) {
                        searchStatus.setText("搜索未完成，请换一个关键词");
                    }
                });
            }
        });
    }

    private List<Document> searchDocuments(String query, String category,
                                           String source, boolean fullText) {
        StringBuilder sql = new StringBuilder("SELECT d.* FROM documents d");
        List<String> args = new ArrayList<>();
        boolean hasQuery = !query.isEmpty();
        if (hasQuery && !fullText) {
            String tokens = buildFtsQuery(query);
            if (!tokens.isEmpty()) {
                sql.append(" JOIN search_idx s ON s.docid=d.id");
            }
        }
        sql.append(" WHERE d.id NOT IN (SELECT document_id FROM local_deleted)");
        if (!category.isEmpty()) {
            sql.append(" AND d.category=?");
            args.add(category);
        }
        if (!source.isEmpty()) {
            sql.append(" AND d.source_type=?");
            args.add(source);
        }
        if (hasQuery) {
            String tokens = buildFtsQuery(query);
            if (fullText) {
                sql.append(" AND (d.title LIKE ? OR d.author LIKE ? OR d.content LIKE ?)");
                String like = "%" + query + "%";
                Collections.addAll(args, like, like, like);
            } else if (!tokens.isEmpty()) {
                sql.append(" AND s.tokens MATCH ?");
                args.add(tokens);
            } else {
                sql.append(" AND (d.title LIKE ? OR d.author LIKE ? OR d.mentioned_books_json LIKE ?)");
                String like = "%" + query + "%";
                Collections.addAll(args, like, like, like);
            }
        }
        if (hasQuery) {
            sql.append(" ORDER BY CASE WHEN d.title LIKE ? THEN 0 WHEN d.author LIKE ? THEN 1 ELSE 2 END,")
                    .append(" d.published_at DESC,d.hot_score DESC,d.id DESC");
            String like = "%" + query + "%";
            Collections.addAll(args, like, like);
        } else {
            sql.append(" ORDER BY d.published_at DESC,d.id DESC");
        }
        sql.append(" LIMIT 250");
        List<Document> found = queryDocuments(sql.toString(), args.toArray(new String[0]));
        if (!found.isEmpty() || !hasQuery || fullText) {
            return found;
        }

        // A title/book lookup should still find an exact quote inside a long review.
        StringBuilder fallback = new StringBuilder("SELECT * FROM documents WHERE " +
                "(title LIKE ? OR author LIKE ? OR content LIKE ?) " +
                "AND id NOT IN (SELECT document_id FROM local_deleted)");
        List<String> fallbackArgs = new ArrayList<>();
        String like = "%" + query + "%";
        Collections.addAll(fallbackArgs, like, like, like);
        if (!category.isEmpty()) {
            fallback.append(" AND category=?");
            fallbackArgs.add(category);
        }
        if (!source.isEmpty()) {
            fallback.append(" AND source_type=?");
            fallbackArgs.add(source);
        }
        fallback.append(" ORDER BY published_at DESC,hot_score DESC,id DESC LIMIT 250");
        return queryDocuments(fallback.toString(), fallbackArgs.toArray(new String[0]));
    }

    private View buildBooks() {
        LinearLayout page = column();
        page.setBackgroundColor(BG);

        LinearLayout header = column();
        header.setPadding(dp(17), dp(15), dp(17), dp(14));
        header.setBackground(gradient(TEAL_DARK, TEAL, 0));
        TextView title = text("书名聚合", 23, Color.WHITE, Typeface.BOLD);
        header.addView(title);
        TextView subtitle = text("按评论数量聚合；同一本书可追溯全部相关楼内回复", 12,
                Color.argb(220, 255, 255, 255), Typeface.NORMAL);
        addWithTop(header, subtitle, 3);
        LinearLayout input = row();
        input.setGravity(Gravity.CENTER_VERTICAL);
        input.setPadding(dp(12), 0, dp(12), 0);
        input.setBackground(round(Color.WHITE, 13));
        input.setElevation(dp(2));
        TextView icon = text("⌕", 20, TEAL, Typeface.BOLD);
        input.addView(icon);
        bookField = new EditText(this);
        bookField.setSingleLine(true);
        bookField.setBackgroundColor(Color.TRANSPARENT);
        bookField.setTextColor(TEXT);
        bookField.setTextSize(15);
        bookField.setHint("搜索书名");
        bookField.setHintTextColor(Color.rgb(145, 153, 151));
        bookField.setPadding(dp(8), 0, 0, 0);
        input.addView(bookField, new LinearLayout.LayoutParams(0, dp(49), 1f));
        addWithTop(header, input, 12);
        page.addView(header);

        bookList = new ListView(this);
        configureListFeedback(bookList);
        bookList.setDivider(null);
        bookList.setDividerHeight(0);
        bookList.setClipToPadding(false);
        bookList.setPadding(dp(11), dp(8), dp(11), dp(64));
        bookList.setBackgroundColor(BG);
        bookAdapter = new BookAdapter();
        bookList.setAdapter(bookAdapter);
        page.addView(bookList, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        bookList.setOnScrollListener(new AbsListView.OnScrollListener() {
            @Override
            public void onScrollStateChanged(AbsListView view, int scrollState) {
            }

            @Override
            public void onScroll(AbsListView view, int firstVisibleItem,
                                 int visibleItemCount, int totalItemCount) {
                if (!booksLoading && !booksEnded && totalItemCount > 0
                        && firstVisibleItem + visibleItemCount >= totalItemCount - 7) {
                    loadBooks(false);
                }
            }
        });
        bookList.setOnItemClickListener((parent, view, position, id) -> {
            if (position >= 0 && position < books.size()) {
                showBookDetail(books.get(position));
            }
        });
        bookField.addTextChangedListener(new TextWatcher() {
            @Override
            public void beforeTextChanged(CharSequence s, int start, int count, int after) {
            }

            @Override
            public void onTextChanged(CharSequence s, int start, int before, int count) {
                bookQuery = s.toString().trim();
                loadBooks(true);
            }

            @Override
            public void afterTextChanged(Editable s) {
            }
        });
        books.clear();
        bookOffset = 0;
        booksEnded = false;
        loadBooks(true);
        return page;
    }

    private void loadBooks(boolean reset) {
        if (booksLoading && !reset) {
            return;
        }
        if (reset) {
            bookOffset = 0;
            booksEnded = false;
            books.clear();
            if (bookAdapter != null) {
                bookAdapter.notifyDataSetChanged();
            }
        }
        booksLoading = true;
        final String query = bookQuery;
        final int offset = bookOffset;
        executor.execute(() -> {
            List<Book> loaded = new ArrayList<>();
            String base = "SELECT id,title,title_norm,review_count,best_document_id," +
                    "latest_at,sources_json FROM books WHERE " +
                    "title NOT LIKE '% · 楼中楼' AND title NOT LIKE '%近期扫书%' " +
                    "AND title NOT LIKE '%书单%' AND title NOT LIKE '%记录%'";
            String[] args;
            if (query.isEmpty()) {
                args = new String[]{String.valueOf(120), String.valueOf(offset)};
                base += " ORDER BY review_count DESC,latest_at DESC LIMIT ? OFFSET ?";
            } else {
                args = new String[]{"%" + query + "%", String.valueOf(120), String.valueOf(offset)};
                base += " AND (title LIKE ? OR title_norm LIKE ?) " +
                        "ORDER BY review_count DESC,latest_at DESC LIMIT ? OFFSET ?";
                args = new String[]{"%" + query + "%", "%" + compact(query) + "%",
                        String.valueOf(120), String.valueOf(offset)};
            }
            Cursor cursor = db.rawQuery(base, args);
            try {
                while (cursor.moveToNext()) {
                    loaded.add(Book.fromCursor(cursor));
                }
            } finally {
                cursor.close();
            }
            mainHandler.post(() -> {
                if (bookAdapter == null || !query.equals(bookQuery)) {
                    booksLoading = false;
                    return;
                }
                books.addAll(loaded);
                bookOffset += loaded.size();
                booksEnded = loaded.size() < 120;
                booksLoading = false;
                bookAdapter.notifyDataSetChanged();
            });
        });
    }

    private void showBookDetail(Book book) {
        detailOpen = true;
        detailBackTab = 2;
        bottomBar.setVisibility(View.GONE);
        content.removeAllViews();

        LinearLayout page = column();
        page.setBackgroundColor(BG);
        page.addView(simpleToolbar("书名详情", this::returnFromDetail));

        LinearLayout hero = column();
        hero.setPadding(dp(18), dp(16), dp(18), dp(16));
        hero.setBackground(gradient(TEAL_DARK, TEAL, 0));
        TextView title = text(book.displayTitle(), 22, Color.WHITE, Typeface.BOLD);
        title.setLineSpacing(0, 1.15f);
        hero.addView(title);
        TextView meta = text("评论聚合 " + book.reviewCount + " 条 · " +
                (book.latestAt.isEmpty() ? "日期未知" : "最近 " + book.latestAt),
                12, Color.argb(220, 255, 255, 255), Typeface.NORMAL);
        addWithTop(hero, meta, 6);
        TextView sources = text(book.sourcesText(), 12, Color.WHITE, Typeface.BOLD);
        sources.setPadding(dp(9), dp(5), dp(9), dp(5));
        sources.setBackground(round(Color.argb(38, 255, 255, 255), 11));
        addWithTop(hero, sources, 8);
        page.addView(hero);

        TextView status = text("正在整理楼内评论…", 13, MUTED, Typeface.NORMAL);
        status.setPadding(dp(17), dp(12), dp(17), dp(7));
        page.addView(status);
        ListView list = new ListView(this);
        configureListFeedback(list);
        list.setDivider(null);
        list.setDividerHeight(0);
        list.setPadding(dp(10), 0, dp(10), dp(12));
        list.setClipToPadding(false);
        list.setBackgroundColor(BG);
        page.addView(list, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));
        content.addView(page);

        executor.execute(() -> {
            List<Document> related = new ArrayList<>();
            String candidates = "SELECT d.* FROM documents d WHERE (d.title_norm=?" +
                    " OR instr(d.mentioned_books_json, ?)>0)" +
                    " AND d.id NOT IN (SELECT document_id FROM local_deleted)" +
                    " ORDER BY d.published_at DESC,d.hot_score DESC,d.id DESC LIMIT 300";
            Cursor cursor = db.rawQuery(candidates,
                    new String[]{book.titleNorm, book.title});
            try {
                while (cursor.moveToNext()) {
                    related.add(Document.fromCursor(cursor));
                }
            } finally {
                cursor.close();
            }
            if (related.isEmpty()) {
                Document best = loadDocument(book.bestDocumentId);
                if (best != null) {
                    related.add(best);
                }
            }
            final List<Document> shown = related;
            mainHandler.post(() -> {
                status.setText("找到 " + shown.size() + " 条关联内容 · 点击可阅读全文");
                list.setAdapter(new DocumentAdapter(shown, book.title));
                list.setOnItemClickListener((parent, view, position, id) ->
                        openDocument(shown.get(position).id));
            });
        });
    }

    private View buildFavorites() {
        LinearLayout page = column();
        page.setBackgroundColor(BG);
        LinearLayout header = column();
        header.setPadding(dp(17), dp(16), dp(17), dp(14));
        header.setBackground(gradient(TEAL_DARK, TEAL, 0));
        TextView title = text("我的收藏", 23, Color.WHITE, Typeface.BOLD);
        header.addView(title);
        TextView subtitle = text("收藏状态仅保存在本机", 12,
                Color.argb(220, 255, 255, 255), Typeface.NORMAL);
        addWithTop(header, subtitle, 3);
        page.addView(header);

        List<Document> favorites = favoritesDocuments();
        TextView count = text(favorites.size() + " 条收藏", 13, MUTED, Typeface.BOLD);
        count.setPadding(dp(17), dp(12), dp(17), dp(5));
        page.addView(count);

        if (favorites.isEmpty()) {
            LinearLayout empty = column();
            empty.setGravity(Gravity.CENTER_HORIZONTAL);
            empty.setPadding(dp(24), dp(55), dp(24), dp(30));
            TextView star = text("☆", 45, GOLD, Typeface.NORMAL);
            star.setGravity(Gravity.CENTER);
            empty.addView(star);
            TextView emptyTitle = text("还没有收藏内容", 18, TEXT, Typeface.BOLD);
            emptyTitle.setGravity(Gravity.CENTER);
            addWithTop(empty, emptyTitle, 10);
            TextView emptyBody = text("阅读评论时点一下“收藏”，之后再回来慢慢看。", 13,
                    MUTED, Typeface.NORMAL);
            emptyBody.setGravity(Gravity.CENTER);
            addWithTop(empty, emptyBody, 7);
            TextView browse = text("去搜索", 14, Color.WHITE, Typeface.BOLD);
            browse.setGravity(Gravity.CENTER);
            browse.setPadding(dp(22), dp(10), dp(22), dp(10));
            browse.setBackground(rippleRound(PINK, Color.TRANSPARENT, 14,
                    Color.argb(55, 255, 255, 255)));
            browse.setOnClickListener(v -> switchTab(1));
            addWithTop(empty, browse, 18);
            page.addView(empty, new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));
        } else {
            ListView list = new ListView(this);
            configureListFeedback(list);
            list.setDivider(null);
            list.setDividerHeight(0);
            list.setPadding(dp(10), 0, dp(10), dp(64));
            list.setClipToPadding(false);
            list.setBackgroundColor(BG);
            list.setAdapter(new DocumentAdapter(favorites, ""));
            list.setOnItemClickListener((parent, view, position, id) ->
                    openDocument(favorites.get(position).id));
            page.addView(list, new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));
        }
        return page;
    }

    private View buildDataManager() {
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        LinearLayout page = column();
        page.setBackgroundColor(BG);
        page.setPadding(0, 0, 0, dp(72));
        scroll.addView(page);

        LinearLayout header = column();
        header.setPadding(dp(17), dp(16), dp(17), dp(16));
        header.setBackground(gradient(TEAL_DEEP, TEAL, 0));
        TextView title = text("数据库管理", 23, Color.WHITE, Typeface.BOLD);
        header.addView(title);
        TextView subtitle = text("导入、导出、单条删除与用户数据备份", 12,
                Color.argb(220, 255, 255, 255), Typeface.NORMAL);
        addWithTop(header, subtitle, 4);

        LinearLayout stats = row();
        stats.setPadding(0, dp(15), 0, 0);
        stats.addView(dataStat(String.valueOf(localDocumentCount()), "本地内容"),
                new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        stats.addView(dataStat(String.valueOf(localBookCount()), "书名聚合"),
                new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        stats.addView(dataStat(String.valueOf(localDeletedCount()), "已删除"),
                new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        header.addView(stats);
        page.addView(header);

        TextView appearance = text("主题颜色", 17, TEXT, Typeface.BOLD);
        appearance.setPadding(dp(16), dp(18), dp(16), dp(6));
        page.addView(appearance);
        HorizontalScrollView themeScroll = new HorizontalScrollView(this);
        themeScroll.setHorizontalScrollBarEnabled(false);
        LinearLayout themeRow = row();
        themeRow.setPadding(dp(16), 0, dp(16), dp(0));
        String currentTheme = preferences.getString("theme_id", "teal");
        themeRow.addView(themeOption("teal", "松石绿", currentTheme,
                Color.rgb(0, 150, 136)), themeOptionParams());
        themeRow.addView(themeOption("ocean", "海盐蓝", currentTheme,
                Color.rgb(30, 136, 229)), themeOptionParams());
        themeRow.addView(themeOption("amber", "琥珀棕", currentTheme,
                Color.rgb(166, 106, 46)), themeOptionParams());
        themeRow.addView(themeOption("rose", "樱雾粉", currentTheme,
                Color.rgb(199, 91, 122)), themeOptionParams());
        themeRow.addView(themeOption("violet", "暮云紫", currentTheme,
                Color.rgb(126, 87, 194)), themeOptionParams());
        themeScroll.addView(themeRow);
        page.addView(themeScroll, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        LinearLayout hapticCard = row();
        hapticCard.setGravity(Gravity.CENTER_VERTICAL);
        hapticCard.setPadding(dp(16), dp(12), dp(12), dp(12));
        hapticCard.setBackground(rippleRound(Color.WHITE, Color.TRANSPARENT, 14,
                Color.argb(28, 0, 0, 0)));
        LinearLayout hapticText = column();
        TextView hapticTitle = text("点击震动", 14, TEXT, Typeface.BOLD);
        hapticText.addView(hapticTitle);
        TextView hapticHint = text("默认关闭；开启后仅提供轻微触感", 11, MUTED,
                Typeface.NORMAL);
        addWithTop(hapticText, hapticHint, 3);
        hapticCard.addView(hapticText, new LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        Switch hapticSwitch = new Switch(this);
        hapticSwitch.setChecked(preferences.getBoolean("haptic_enabled", false));
        hapticSwitch.setButtonTintList(ColorStateList.valueOf(TEAL));
        hapticSwitch.setOnCheckedChangeListener((button, checked) -> {
            preferences.edit().putBoolean("haptic_enabled", checked).apply();
            toast(checked ? "已开启轻微点击震动" : "已关闭点击震动");
        });
        hapticCard.addView(hapticSwitch, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, dp(48)));
        hapticCard.setOnClickListener(v -> hapticSwitch.toggle());
        LinearLayout.LayoutParams hapticParams = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        hapticParams.setMargins(dp(16), dp(10), dp(16), 0);
        page.addView(hapticCard, hapticParams);

        TextView section = text("备份与迁移", 17, TEXT, Typeface.BOLD);
        section.setPadding(dp(16), dp(18), dp(16), dp(2));
        page.addView(section);

        LinearLayout exportCard = dataActionCard(
                "导出扫书",
                "将全部未删除内容、正文和来源关系导出为 UTF-8 JSONL 文件，可在其他设备重新导入。",
                "选择导出位置",
                v -> requestDataExport());
        addWithTop(page, exportCard, 10);

        LinearLayout importCard = dataActionCard(
                "导入扫书（单条或批量）",
                "选择由本应用导出的 JSONL 文件。单条文件可直接导入，批量文件按 canonical_key 自动查重。",
                "选择单条或批量文件",
                v -> requestDataImport());
        addWithTop(page, importCard, 10);

        LinearLayout clipboardCard = dataActionCard(
                "从剪切板导入文本",
                "识别书名、作者、平台、评分、看点、雷点等字段；包含多条扫书时会自动分段。",
                "读取并识别剪切板",
                v -> importFromClipboard());
        addWithTop(page, clipboardCard, 10);

        int deleted = (int) localDeletedCount();
        LinearLayout restoreCard = dataActionCard(
                "恢复本地删除",
                deleted == 0 ? "当前没有已删除内容。" :
                        "恢复 " + deleted + " 条仅在本机隐藏的内容，并重新加入搜索与书名聚合。",
                deleted == 0 ? "无需恢复" : "恢复全部",
                v -> confirmRestoreAll());
        if (deleted == 0) {
            setChildrenEnabled(restoreCard, false);
        }
        addWithTop(page, restoreCard, 10);

        TextView userSection = text("用户数据备份", 17, TEXT, Typeface.BOLD);
        userSection.setPadding(dp(16), dp(20), dp(16), dp(2));
        page.addView(userSection);

        LinearLayout userBackupCard = dataActionCard(
                "备份用户数据",
                "导出收藏、主题颜色和震动开关设置。不会重复打包离线正文数据库。",
                "导出用户备份",
                v -> requestUserBackupExport());
        addWithTop(page, userBackupCard, 10);

        LinearLayout userRestoreCard = dataActionCard(
                "恢复用户数据",
                "从 JSON 备份恢复收藏与界面设置；无效或已不存在的收藏会安全跳过。",
                "选择用户备份",
                v -> requestUserBackupImport());
        addWithTop(page, userRestoreCard, 10);

        LinearLayout statusCard = column();
        statusCard.setPadding(dp(15), dp(14), dp(15), dp(14));
        statusCard.setBackground(round(TEAL_SOFT, 14));
        TextView statusTitle = text("操作状态", 13, TEAL_DARK, Typeface.BOLD);
        statusCard.addView(statusTitle);
        dataStatus = text(preferences.getString("last_data_message",
                        "本地数据只保存在这台设备；删除与导入都会立即写入本地数据库。"),
                12, MUTED, Typeface.NORMAL);
        dataStatus.setLineSpacing(0, 1.35f);
        addWithTop(statusCard, dataStatus, 6);
        addWithTop(page, statusCard, 16);

        long cleanedDuplicates = metaLong("removed_duplicates", 0);
        long cleanedReplies = metaLong("removed_meaningless", 0);
        long cleanedRecentShort = metaLong("removed_recent_short", 0);
        TextView format = text(
                "导入导出范围包含扫书、推书、排雷、讨论与求书记录。" +
                        (cleanedDuplicates > 0
                                ? " 内置资料库已清理 " + formatCompact(cleanedDuplicates) +
                                " 条高相似重复内容。"
                                : "") +
                        (cleanedReplies > 0
                                ? " 另过滤 " + formatCompact(cleanedReplies) +
                                " 条无意义短回复。"
                                : "") +
                        (cleanedRecentShort > 0
                                ? " 近期不足 50 字的内容已清理 " +
                                formatCompact(cleanedRecentShort) + " 条。"
                                : "") +
                        " 单条删除可在阅读页执行；单条导出也在阅读页操作。" +
                        " 本应用不下载小说正文，只管理已采集的评论与来源信息。",
                11, MUTED, Typeface.NORMAL);
        format.setLineSpacing(0, 1.4f);
        format.setPadding(dp(18), dp(15), dp(18), 0);
        page.addView(format);
        return scroll;
    }

    private View themeOption(String id, String label, String currentTheme, int color) {
        boolean selected = id.equals(currentTheme);
        LinearLayout option = row();
        option.setGravity(Gravity.CENTER_VERTICAL);
        option.setPadding(dp(12), dp(9), dp(14), dp(9));
        option.setBackground(rippleRound(
                selected ? TEAL_PALE : Color.WHITE,
                selected ? TEAL_DARK : LINE,
                15,
                Color.argb(35, 0, 0, 0)));
        View swatch = new View(this);
        swatch.setBackground(round(color, 9));
        option.addView(swatch, new LinearLayout.LayoutParams(dp(18), dp(18)));
        TextView name = text(label, 13, selected ? TEAL_DARK : TEXT,
                selected ? Typeface.BOLD : Typeface.NORMAL);
        name.setPadding(dp(8), 0, 0, 0);
        option.addView(name);
        option.setClickable(true);
        option.setFocusable(true);
        option.setOnClickListener(v -> {
            preferences.edit().putString("theme_id", id).apply();
            applySelectedTheme();
            configureWindow();
            showMainShell();
            switchTab(4);
            toast("已切换为「" + label + "」");
        });
        return option;
    }

    private LinearLayout.LayoutParams themeOptionParams() {
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        params.rightMargin = dp(8);
        return params;
    }

    private View dataStat(String value, String label) {
        LinearLayout box = column();
        box.setGravity(Gravity.CENTER);
        TextView number = text(value, 19, Color.WHITE, Typeface.BOLD);
        number.setGravity(Gravity.CENTER);
        box.addView(number);
        TextView caption = text(label, 11, Color.argb(215, 255, 255, 255), Typeface.NORMAL);
        caption.setGravity(Gravity.CENTER);
        box.addView(caption);
        return box;
    }

    private LinearLayout dataActionCard(String title, String description,
                                        String buttonLabel, View.OnClickListener listener) {
        LinearLayout card = column();
        card.setPadding(dp(16), dp(15), dp(16), dp(14));
        card.setBackground(rippleRound(Color.WHITE, Color.TRANSPARENT, 15,
                Color.argb(30, 0, 0, 0)));
        card.setElevation(dp(2));
        card.setClickable(true);
        card.setFocusable(true);
        TextView heading = text(title, 17, TEXT, Typeface.BOLD);
        card.addView(heading);
        TextView body = text(description, 12, MUTED, Typeface.NORMAL);
        body.setLineSpacing(0, 1.35f);
        addWithTop(card, body, 7);
        TextView button = actionButton(buttonLabel, TEAL_PALE, TEAL_DARK);
        button.setOnClickListener(dataBusy ? v -> toast("请等待当前操作完成") : listener);
        card.setOnClickListener(dataBusy
                ? v -> toast("请等待当前操作完成")
                : v -> listener.onClick(v));
        addWithTop(card, button, 11);
        return card;
    }

    private void setChildrenEnabled(ViewGroup root, boolean enabled) {
        for (int i = 0; i < root.getChildCount(); i++) {
            View child = root.getChildAt(i);
            child.setEnabled(enabled);
            child.setAlpha(enabled ? 1f : 0.5f);
            if (child instanceof ViewGroup) {
                setChildrenEnabled((ViewGroup) child, enabled);
            }
        }
    }

    private CharSequence formatScanContent(String content) {
        String raw = stripSourceMetadata(safe(content))
                .replace("\r\n", "\n")
                .replace('\r', '\n')
                .replaceAll("看高清大图[，,]?\\s*打开贴吧App", "")
                .replaceAll("\\n{3,}", "\n\n")
                .trim();
        Pattern knownLabel = Pattern.compile(
                "^(书名|作者|平台|状态|字数|时长|简介|评语|剧情|剧情方面|" +
                        "男主|男主方面|女主|女主方面|看点|优点|雷点|毒点|郁闷|" +
                        "郁闷点|防御|防御建议|文笔|情节|感情|评分|综合评价|" +
                        "CC|FC|标签|推荐|推荐指数)[：:]\\s*(.*)$",
                Pattern.CASE_INSENSITIVE);
        SpannableStringBuilder formatted = new SpannableStringBuilder();
        boolean previousBlank = true;
        for (String sourceLine : raw.split("\n", -1)) {
            String line = sourceLine.trim();
            if (line.isEmpty()) {
                if (formatted.length() > 0 && !previousBlank) {
                    formatted.append("\n\n");
                    previousBlank = true;
                }
                continue;
            }
            Matcher known = knownLabel.matcher(line);
            if (known.matches()) {
                if (formatted.length() > 0 && !previousBlank) {
                    formatted.append("\n\n");
                }
                String label = known.group(1) + "：";
                int start = formatted.length();
                formatted.append(label);
                formatted.setSpan(new StyleSpan(Typeface.BOLD), start, formatted.length(),
                        SpannableStringBuilder.SPAN_EXCLUSIVE_EXCLUSIVE);
                formatted.setSpan(new ForegroundColorSpan(TEAL_DARK),
                        start, formatted.length(),
                        SpannableStringBuilder.SPAN_EXCLUSIVE_EXCLUSIVE);
                formatted.append(known.group(2).trim());
                previousBlank = false;
            } else {
                if (formatted.length() > 0) {
                    formatted.append(previousBlank ? "" : "\n");
                }
                formatted.append(line);
                previousBlank = false;
            }
        }
        while (formatted.length() > 0 &&
                formatted.charAt(formatted.length() - 1) == '\n') {
            formatted.delete(formatted.length() - 1, formatted.length());
        }
        return formatted;
    }

    private void requestDataExport() {
        if (dataBusy) {
            return;
        }
        String stamp = new SimpleDateFormat("yyyyMMdd-HHmmss", Locale.ROOT)
                .format(new Date());
        Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("application/x-ndjson");
        intent.putExtra(Intent.EXTRA_TITLE, "扫书导出-" + stamp + ".jsonl");
        startActivityForResult(intent, REQUEST_EXPORT_DATA);
    }

    private void requestDataImport() {
        if (dataBusy) {
            return;
        }
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("*/*");
        startActivityForResult(intent, REQUEST_IMPORT_DATA);
    }

    private void importFromClipboard() {
        if (dataBusy) {
            toast("请等待当前操作完成");
            return;
        }
        showClipboardInputDialog(readClipboardText());
    }

    private String readClipboardText() {
        ClipboardManager manager =
                (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
        if (manager == null || !manager.hasPrimaryClip()
                || manager.getPrimaryClip() == null
                || manager.getPrimaryClip().getItemCount() == 0) {
            return "";
        }
        ClipData clip = manager.getPrimaryClip();
        StringBuilder builder = new StringBuilder();
        for (int i = 0; i < clip.getItemCount(); i++) {
            CharSequence value = clip.getItemAt(i).coerceToText(this);
            if (value != null) {
                if (builder.length() > 0) {
                    builder.append('\n');
                }
                builder.append(value);
            }
        }
        return builder.toString().trim();
    }

    private void showClipboardInputDialog(String initialText) {
        EditText input = new EditText(this);
        input.setText(initialText);
        input.setHint("可在此粘贴或手动输入扫书文本…");
        input.setGravity(Gravity.TOP | Gravity.START);
        input.setTextSize(14);
        input.setTextColor(TEXT);
        input.setHintTextColor(MUTED);
        input.setSingleLine(false);
        input.setMinLines(10);
        input.setMaxLines(16);
        input.setPadding(dp(12), dp(10), dp(12), dp(10));
        input.setBackground(rippleRound(TEAL_SOFT, LINE, 12,
                Color.argb(25, 0, 0, 0)));
        android.app.AlertDialog dialog = new android.app.AlertDialog.Builder(this)
                .setTitle("从剪切板导入文本")
                .setMessage("已预填剪切板内容，可直接修改、补充或手动输入。")
                .setView(input)
                .setNegativeButton("取消", null)
                .setPositiveButton("识别", null)
                .create();
        dialog.setOnShowListener(ignored -> dialog.getButton(
                        android.app.AlertDialog.BUTTON_POSITIVE)
                .setOnClickListener(v -> {
                    String text = input.getText().toString().trim();
                    if (text.isEmpty()) {
                        toast("请输入或粘贴扫书文本");
                        return;
                    }
                    if (text.length() > 2_000_000) {
                        toast("文本过大，请控制在 200 万字符以内");
                        return;
                    }
                    List<ClipboardEntry> entries = parseClipboardEntries(text);
                    if (entries.isEmpty()) {
                        toast("没有识别到有效扫书内容");
                        return;
                    }
                    dialog.dismiss();
                    showClipboardPreview(entries);
                }));
        dialog.show();
    }

    private void showClipboardPreview(List<ClipboardEntry> entries) {
        StringBuilder preview = new StringBuilder();
        preview.append("识别到 ").append(entries.size()).append(" 条扫书：\n\n");
        int shown = Math.min(entries.size(), 8);
        for (int i = 0; i < shown; i++) {
            ClipboardEntry entry = entries.get(i);
            preview.append(i + 1).append(". ").append(entry.title);
            if (!entry.author.isEmpty()) {
                preview.append(" · ").append(entry.author);
            }
            preview.append('\n');
        }
        if (entries.size() > shown) {
            preview.append("…另有 ").append(entries.size() - shown).append(" 条");
        }
        preview.append("\n\n导入时会自动按正文去重。");
        new android.app.AlertDialog.Builder(this)
                .setTitle("确认导入剪切板")
                .setMessage(preview.toString())
                .setNegativeButton("取消", null)
                .setPositiveButton("导入", (dialog, which) ->
                        startClipboardImport(entries))
                .show();
    }

    private void startClipboardImport(List<ClipboardEntry> entries) {
        if (dataBusy) {
            return;
        }
        dataBusy = true;
        updateDataStatus("正在识别并写入剪切板扫书…");
        executor.execute(() -> {
            try {
                ImportResult result = insertClipboardEntries(entries);
                finishDataOperation("剪切板导入完成：新增 " + result.inserted +
                        " 条，跳过重复 " + result.skipped + " 条。", false);
            } catch (Exception error) {
                finishDataOperation("剪切板导入失败：" + readableError(error), true);
            }
        });
    }

    private ImportResult insertClipboardEntries(List<ClipboardEntry> entries)
            throws Exception {
        int inserted = 0;
        int skipped = 0;
        int sources = 0;
        String importedAt = isoNow();
        String today = new SimpleDateFormat("yyyy-MM-dd", Locale.ROOT)
                .format(new Date());
        db.beginTransaction();
        try {
            int sequence = 0;
            for (ClipboardEntry entry : entries) {
                String content = entry.content.trim();
                if (compact(content).length() < 20) {
                    skipped++;
                    continue;
                }
                String canonicalKey = deterministicKey(content, entry.title);
                if (findDocumentByKey(canonicalKey) != null) {
                    skipped++;
                    continue;
                }
                String mentioned = mentionedBooksJson(content, entry.title);
                long word = compact(content).length();
                db.execSQL("INSERT INTO documents(" +
                                "canonical_key,title,title_norm,author,author_norm," +
                                "content,category,source_type,forum,mname,zname," +
                                "published_at,source_url,word,hot_score," +
                                "mentioned_books_json) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                        new Object[]{canonicalKey, entry.title, compact(entry.title),
                                entry.author, compact(entry.author), content, "扫书",
                                "剪贴板", "", "剪切板文本导入", entry.title, today,
                                "", word, 0, mentioned});
                long id = db.compileStatement("SELECT last_insert_rowid()")
                        .simpleQueryForLong();
                indexDocumentSearch(id, entry.title, entry.author, mentioned);
                adjustBookIndex(entry.title, mentioned, "剪贴板", today,
                        id, word, 1);
                insertSourceIfMissing(id, "clipboard",
                        "clipboard:" + importedAt + ":" + sequence, "");
                inserted++;
                sources++;
                sequence++;
            }
            db.setTransactionSuccessful();
        } finally {
            db.endTransaction();
        }
        return new ImportResult(inserted, 0, skipped, sources);
    }

    private List<ClipboardEntry> parseClipboardEntries(String text) {
        String normalized = text.replace("\r\n", "\n").replace('\r', '\n')
                .replace("\u200b", "").trim();
        String[] lines = normalized.split("\n", -1);
        List<Integer> starts = new ArrayList<>();
        for (int i = 0; i < lines.length; i++) {
            String line = lines[i].trim();
            if (line.isEmpty()) {
                continue;
            }
            boolean explicitTitle = line.matches("^(书名|作品名)\\s*[：:].+");
            boolean standaloneBook = line.matches("^《[^》]{2,80}》\\s*$");
            boolean numberedHeading = line.matches(
                    "^(\\d{1,3}|[一二三四五六七八九十百]{1,4})[、.．]\\s*.+")
                    && line.length() <= 80;
            boolean hasBookMarker = line.contains("《") && line.contains("》");
            boolean nearbyField = false;
            if (numberedHeading) {
                for (int j = i + 1; j < Math.min(lines.length, i + 5); j++) {
                    if (lines[j].matches("^(作者|平台|状态|字数|评分|简介|看点|雷点).*")) {
                        nearbyField = true;
                        break;
                    }
                }
            }
            if (explicitTitle || standaloneBook
                    || (numberedHeading && (hasBookMarker || nearbyField))) {
                starts.add(i);
            }
        }
        List<ClipboardEntry> entries = new ArrayList<>();
        if (starts.isEmpty()) {
            ClipboardEntry entry = parseClipboardSegment(normalized);
            if (entry != null) {
                entries.add(entry);
            }
            return entries;
        }
        for (int index = 0; index < starts.size(); index++) {
            int start = starts.get(index);
            int end = index + 1 < starts.size() ? starts.get(index + 1) : lines.length;
            StringBuilder segment = new StringBuilder();
            for (int line = start; line < end; line++) {
                if (segment.length() > 0) {
                    segment.append('\n');
                }
                segment.append(lines[line]);
            }
            ClipboardEntry entry = parseClipboardSegment(segment.toString());
            if (entry != null) {
                entries.add(entry);
            }
        }
        return entries;
    }

    private ClipboardEntry parseClipboardSegment(String segment) {
        String content = segment.trim();
        Matcher titleMatcher = Pattern.compile(
                "(?m)^\\s*书名\\s*[：:]\\s*《?([^》\\n]{2,80})").matcher(content);
        String title = "";
        if (titleMatcher.find()) {
            title = titleMatcher.group(1).trim();
        }
        if (title.isEmpty()) {
            titleMatcher = Pattern.compile(
                    "(?m)^\\s*(?:\\d{1,3}|[一二三四五六七八九十百]{1,4})[、.．]\\s*《([^》]{2,80})》")
                    .matcher(content);
            if (titleMatcher.find()) {
                title = titleMatcher.group(1).trim();
            }
        }
        if (title.isEmpty()) {
            titleMatcher = Pattern.compile("(?m)^\\s*《([^》]{2,80})》\\s*$")
                    .matcher(content);
            if (titleMatcher.find()) {
                title = titleMatcher.group(1).trim();
            }
        }
        if (title.isEmpty()) {
            String firstLine = content.split("\\n", 2)[0].trim();
            firstLine = firstLine.replaceFirst(
                    "^(?:\\d{1,3}|[一二三四五六七八九十百]{1,4})[、.．]\\s*", "");
            firstLine = firstLine.replaceFirst("^(扫书|推书|排雷|简评|点评)\\s*[：:]?\\s*", "");
            firstLine = firstLine.replaceAll("《([^》]+)》", "$1");
            firstLine = firstLine.split("\\s*(?:作者|平台|状态|字数|评分)\\s*[：:]", 2)[0];
            title = cleanDisplayTitle(firstLine);
        }
        if ("未命名内容".equals(title)) {
            return null;
        }
        if (title.length() > 80) {
            title = title.substring(0, 80).trim();
        }
        Matcher authorMatcher = Pattern.compile(
                "(?m)^\\s*作者\\s*[：:]\\s*([^\\n|｜]{1,60})").matcher(content);
        String author = "";
        if (authorMatcher.find()) {
            author = authorMatcher.group(1).split("[,，;；|｜]", 2)[0].trim();
        }
        return new ClipboardEntry(title, author, content);
    }

    private String mentionedBooksJson(String content, String title) {
        LinkedHashSet<String> books = new LinkedHashSet<>();
        Matcher matcher = Pattern.compile("《([^》\\n]{2,80})》").matcher(content);
        while (matcher.find()) {
            books.add(matcher.group(1).trim());
        }
        if (title != null && title.length() >= 2) {
            books.add(title);
        }
        JSONArray array = new JSONArray();
        for (String book : books) {
            array.put(book);
        }
        return array.toString();
    }

    private void requestSingleExport(Document document) {
        if (dataBusy) {
            toast("请等待当前操作完成");
            return;
        }
        pendingSingleExportId = document.id;
        String safeName = document.title.replaceAll("[\\\\/:*?\"<>|]+", "-")
                .replaceAll("\\s+", " ").trim();
        if (safeName.isEmpty()) {
            safeName = "单条扫书";
        }
        if (safeName.length() > 48) {
            safeName = safeName.substring(0, 48);
        }
        Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("application/x-ndjson");
        intent.putExtra(Intent.EXTRA_TITLE, safeName + ".jsonl");
        startActivityForResult(intent, REQUEST_EXPORT_SINGLE);
    }

    private void requestUserBackupExport() {
        if (dataBusy) {
            return;
        }
        String stamp = new SimpleDateFormat("yyyyMMdd-HHmmss", Locale.ROOT)
                .format(new Date());
        Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("application/json");
        intent.putExtra(Intent.EXTRA_TITLE, "扫书新典用户备份-" + stamp + ".json");
        startActivityForResult(intent, REQUEST_EXPORT_USER_BACKUP);
    }

    private void requestUserBackupImport() {
        if (dataBusy) {
            return;
        }
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("application/json");
        startActivityForResult(intent, REQUEST_IMPORT_USER_BACKUP);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (resultCode != RESULT_OK || data == null || data.getData() == null) {
            return;
        }
        Uri uri = data.getData();
        if (requestCode == REQUEST_EXPORT_DATA) {
            startDataExport(uri);
        } else if (requestCode == REQUEST_IMPORT_DATA) {
            startDataImport(uri);
        } else if (requestCode == REQUEST_EXPORT_SINGLE) {
            startSingleDocumentExport(uri, pendingSingleExportId);
            pendingSingleExportId = -1;
        } else if (requestCode == REQUEST_EXPORT_USER_BACKUP) {
            startUserBackupExport(uri);
        } else if (requestCode == REQUEST_IMPORT_USER_BACKUP) {
            startUserBackupImport(uri);
        }
    }

    private void startDataExport(Uri uri) {
        if (dataBusy) {
            return;
        }
        dataBusy = true;
        updateDataStatus("正在导出扫书资料，请保持应用在前台…");
        executor.execute(() -> {
            try {
                ExportResult result = exportData(uri);
                finishDataOperation("导出完成：" + result.documents + " 条内容，" +
                        result.sources + " 条来源关系。", false);
            } catch (Exception error) {
                finishDataOperation("导出失败：" + readableError(error), true);
            }
        });
    }

    private ExportResult exportData(Uri uri) throws Exception {
        OutputStream raw = getContentResolver().openOutputStream(uri);
        if (raw == null) {
            throw new IllegalStateException("无法创建导出文件");
        }
        int documents = 0;
        int sources = 0;
        String exportedAt = isoNow();
        try (BufferedWriter writer = new BufferedWriter(
                new OutputStreamWriter(raw, StandardCharsets.UTF_8))) {
            JSONObject meta = new JSONObject();
            meta.put("kind", "meta");
            meta.put("format", "saoshu-xindian-jsonl");
            meta.put("version", 1);
            meta.put("exported_at", exportedAt);
            meta.put("data_cutoff", metaValue("data_cutoff", ""));
            writer.write(meta.toString());
            writer.newLine();

            Cursor cursor = db.rawQuery(
                    "SELECT d.* FROM documents d " +
                            "WHERE d.id NOT IN (SELECT document_id FROM local_deleted) " +
                            "ORDER BY d.id", null);
            try {
                while (cursor.moveToNext()) {
                    Document document = Document.fromCursor(cursor);
                    JSONObject item = new JSONObject();
                    item.put("kind", "document");
                    item.put("canonical_key", cursor.getString(
                            cursor.getColumnIndexOrThrow("canonical_key")));
                    item.put("title", document.title);
                    item.put("author", document.author);
                    item.put("content", document.content);
                    item.put("category", document.category);
                    item.put("source_type", document.sourceType);
                    item.put("forum", document.forum);
                    item.put("mname", safe(cursor.getString(
                            cursor.getColumnIndexOrThrow("mname"))));
                    item.put("zname", safe(cursor.getString(
                            cursor.getColumnIndexOrThrow("zname"))));
                    item.put("published_at", document.date);
                    item.put("source_url", document.sourceUrl);
                    item.put("word", document.word);
                    item.put("hot_score", cursor.getLong(
                            cursor.getColumnIndexOrThrow("hot_score")));
                    item.put("mentioned_books_json", document.mentionedJson);
                    writer.write(item.toString());
                    writer.newLine();
                    documents++;
                }
            } finally {
                cursor.close();
            }

            Cursor sourceCursor = db.rawQuery(
                    "SELECT d.canonical_key,s.source_kind,s.source_ref,s.source_url " +
                            "FROM document_sources s JOIN documents d ON d.id=s.document_id " +
                            "WHERE d.id NOT IN (SELECT document_id FROM local_deleted) " +
                            "ORDER BY d.id,s.id", null);
            try {
                while (sourceCursor.moveToNext()) {
                    JSONObject source = new JSONObject();
                    source.put("kind", "source");
                    source.put("document_key", safe(sourceCursor.getString(0)));
                    source.put("source_kind", safe(sourceCursor.getString(1)));
                    source.put("source_ref", safe(sourceCursor.getString(2)));
                    source.put("source_url", safe(sourceCursor.getString(3)));
                    writer.write(source.toString());
                    writer.newLine();
                    sources++;
                }
            } finally {
                sourceCursor.close();
            }

            JSONObject end = new JSONObject();
            end.put("kind", "end");
            end.put("documents", documents);
            end.put("sources", sources);
            writer.write(end.toString());
            writer.newLine();
            writer.flush();
        }
        return new ExportResult(documents, sources);
    }

    private void startSingleDocumentExport(Uri uri, long documentId) {
        if (documentId <= 0 || dataBusy) {
            return;
        }
        dataBusy = true;
        updateDataStatus("正在导出单条扫书…");
        executor.execute(() -> {
            try {
                ExportResult result = exportSingleDocument(uri, documentId);
                finishDataOperation("单条扫书导出完成，包含 " + result.sources +
                        " 条来源关系。", false);
            } catch (Exception error) {
                finishDataOperation("单条导出失败：" + readableError(error), true);
            }
        });
    }

    private ExportResult exportSingleDocument(Uri uri, long documentId) throws Exception {
        Cursor cursor = db.rawQuery(
                "SELECT d.* FROM documents d WHERE d.id=? " +
                        "AND d.id NOT IN (SELECT document_id FROM local_deleted)",
                new String[]{String.valueOf(documentId)});
        try {
            if (!cursor.moveToFirst()) {
                throw new IllegalStateException("这条扫书已不存在");
            }
            OutputStream raw = getContentResolver().openOutputStream(uri);
            if (raw == null) {
                throw new IllegalStateException("无法创建单条导出文件");
            }
            Document document = Document.fromCursor(cursor);
            String canonicalKey = safe(cursor.getString(
                    cursor.getColumnIndexOrThrow("canonical_key")));
            int sources = 0;
            try (BufferedWriter writer = new BufferedWriter(
                    new OutputStreamWriter(raw, StandardCharsets.UTF_8))) {
                JSONObject meta = new JSONObject();
                meta.put("kind", "meta");
                meta.put("format", "saoshu-xindian-single-jsonl");
                meta.put("version", 1);
                meta.put("exported_at", isoNow());
                writer.write(meta.toString());
                writer.newLine();

                JSONObject item = new JSONObject();
                item.put("kind", "document");
                item.put("canonical_key", canonicalKey);
                item.put("title", document.title);
                item.put("author", document.author);
                item.put("content", document.content);
                item.put("category", document.category);
                item.put("source_type", document.sourceType);
                item.put("forum", document.forum);
                item.put("mname", safe(cursor.getString(
                        cursor.getColumnIndexOrThrow("mname"))));
                item.put("zname", safe(cursor.getString(
                        cursor.getColumnIndexOrThrow("zname"))));
                item.put("published_at", document.date);
                item.put("source_url", document.sourceUrl);
                item.put("word", document.word);
                item.put("hot_score", cursor.getLong(
                        cursor.getColumnIndexOrThrow("hot_score")));
                item.put("mentioned_books_json", document.mentionedJson);
                writer.write(item.toString());
                writer.newLine();

                Cursor sourceCursor = db.rawQuery(
                        "SELECT source_kind,source_ref,source_url " +
                                "FROM document_sources WHERE document_id=? ORDER BY id",
                        new String[]{String.valueOf(documentId)});
                try {
                    while (sourceCursor.moveToNext()) {
                        JSONObject source = new JSONObject();
                        source.put("kind", "source");
                        source.put("document_key", canonicalKey);
                        source.put("source_kind", safe(sourceCursor.getString(0)));
                        source.put("source_ref", safe(sourceCursor.getString(1)));
                        source.put("source_url", safe(sourceCursor.getString(2)));
                        writer.write(source.toString());
                        writer.newLine();
                        sources++;
                    }
                } finally {
                    sourceCursor.close();
                }
                JSONObject end = new JSONObject();
                end.put("kind", "end");
                end.put("documents", 1);
                end.put("sources", sources);
                writer.write(end.toString());
                writer.newLine();
                writer.flush();
            }
            return new ExportResult(1, sources);
        } finally {
            cursor.close();
        }
    }

    private void startUserBackupExport(Uri uri) {
        if (dataBusy) {
            return;
        }
        dataBusy = true;
        updateDataStatus("正在导出收藏和界面设置…");
        executor.execute(() -> {
            try {
                UserBackupResult result = exportUserBackup(uri);
                finishDataOperation("用户数据备份完成：收藏 " + result.favorites +
                        " 条，主题与震动设置已保存。", false);
            } catch (Exception error) {
                finishDataOperation("用户备份失败：" + readableError(error), true);
            }
        });
    }

    private UserBackupResult exportUserBackup(Uri uri) throws Exception {
        OutputStream raw = getContentResolver().openOutputStream(uri);
        if (raw == null) {
            throw new IllegalStateException("无法创建用户备份文件");
        }
        Set<String> favoriteIds = preferences.getStringSet(
                "favorite_ids", new LinkedHashSet<>());
        JSONArray ids = new JSONArray();
        JSONArray keys = new JSONArray();
        if (favoriteIds != null) {
            for (String id : new LinkedHashSet<>(favoriteIds)) {
                ids.put(id);
                try (Cursor cursor = db.rawQuery(
                        "SELECT canonical_key FROM documents WHERE id=?",
                        new String[]{id})) {
                    if (cursor.moveToFirst()) {
                        keys.put(safe(cursor.getString(0)));
                    }
                }
            }
        }
        JSONObject backup = new JSONObject();
        backup.put("kind", "saoshu-xindian-user-backup");
        backup.put("version", 1);
        backup.put("created_at", isoNow());
        JSONObject settings = new JSONObject();
        settings.put("theme_id", preferences.getString("theme_id", "teal"));
        settings.put("haptic_enabled", preferences.getBoolean("haptic_enabled", false));
        settings.put("favorite_ids", ids);
        settings.put("favorite_keys", keys);
        backup.put("settings", settings);
        try (BufferedWriter writer = new BufferedWriter(
                new OutputStreamWriter(raw, StandardCharsets.UTF_8))) {
            writer.write(backup.toString(2));
            writer.newLine();
        }
        return new UserBackupResult(keys.length());
    }

    private void startUserBackupImport(Uri uri) {
        if (dataBusy) {
            return;
        }
        dataBusy = true;
        updateDataStatus("正在恢复用户收藏与设置…");
        executor.execute(() -> {
            try {
                UserBackupResult result = importUserBackup(uri);
                mainHandler.post(() -> {
                    dataBusy = false;
                    applySelectedTheme();
                    configureWindow();
                    showMainShell();
                    switchTab(4);
                    String message = "用户数据恢复完成：收藏 " + result.favorites +
                            " 条，主题与震动设置已应用。";
                    preferences.edit().putString("last_data_message", message).apply();
                    toast(message);
                });
            } catch (Exception error) {
                finishDataOperation("用户恢复失败：" + readableError(error), true);
            }
        });
    }

    private UserBackupResult importUserBackup(Uri uri) throws Exception {
        InputStream raw = getContentResolver().openInputStream(uri);
        if (raw == null) {
            throw new IllegalStateException("无法读取用户备份文件");
        }
        String content;
        try (BufferedReader reader = new BufferedReader(
                new InputStreamReader(raw, StandardCharsets.UTF_8))) {
            StringBuilder builder = new StringBuilder();
            char[] buffer = new char[4096];
            int count;
            while ((count = reader.read(buffer)) != -1) {
                builder.append(buffer, 0, count);
            }
            content = builder.toString();
        }
        JSONObject backup = new JSONObject(content);
        if (!"saoshu-xindian-user-backup".equals(
                backup.optString("kind", ""))) {
            throw new IllegalArgumentException("不是扫书新典用户备份文件");
        }
        JSONObject settings = backup.optJSONObject("settings");
        if (settings == null) {
            throw new IllegalArgumentException("备份中缺少 settings");
        }
        String theme = settings.optString("theme_id", "teal");
        if (!theme.matches("teal|ocean|amber|rose|violet")) {
            theme = "teal";
        }
        boolean haptic = settings.optBoolean("haptic_enabled", false);
        Set<String> restoredIds = new LinkedHashSet<>();
        JSONArray keys = settings.optJSONArray("favorite_keys");
        boolean hasCanonicalFavorites = keys != null;
        if (keys != null) {
            for (int i = 0; i < keys.length(); i++) {
                String key = keys.optString(i, "");
                if (key.isEmpty()) {
                    continue;
                }
                try (Cursor cursor = db.rawQuery(
                        "SELECT id FROM documents WHERE canonical_key=? " +
                                "AND id NOT IN (SELECT document_id FROM local_deleted)",
                        new String[]{key})) {
                    if (cursor.moveToFirst()) {
                        restoredIds.add(String.valueOf(cursor.getLong(0)));
                    }
                }
            }
        }
        JSONArray ids = settings.optJSONArray("favorite_ids");
        if (!hasCanonicalFavorites && ids != null) {
            for (int i = 0; i < ids.length(); i++) {
                String id = ids.optString(i, "");
                try (Cursor cursor = db.rawQuery(
                        "SELECT 1 FROM documents WHERE id=? " +
                                "AND id NOT IN (SELECT document_id FROM local_deleted)",
                        new String[]{id})) {
                    if (cursor.moveToFirst()) {
                        restoredIds.add(id);
                    }
                }
            }
        }
        preferences.edit()
                .putString("theme_id", theme)
                .putBoolean("haptic_enabled", haptic)
                .putStringSet("favorite_ids", restoredIds)
                .apply();
        return new UserBackupResult(restoredIds.size());
    }

    private void startDataImport(Uri uri) {
        if (dataBusy) {
            return;
        }
        dataBusy = true;
        updateDataStatus("正在读取并查重导入文件…");
        executor.execute(() -> {
            try {
                ImportResult result = importData(uri);
                finishDataOperation("导入完成：新增 " + result.inserted +
                        " 条，恢复 " + result.restored + " 条，跳过重复 " +
                        result.skipped + " 条，补充来源 " + result.sources + " 条。", false);
            } catch (Exception error) {
                finishDataOperation("导入失败：" + readableError(error), true);
            }
        });
    }

    private ImportResult importData(Uri uri) throws Exception {
        InputStream raw = getContentResolver().openInputStream(uri);
        if (raw == null) {
            throw new IllegalStateException("无法读取导入文件");
        }
        int inserted = 0;
        int restored = 0;
        int skipped = 0;
        int sourcesAdded = 0;
        db.beginTransaction();
        try (BufferedReader reader = new BufferedReader(
                new InputStreamReader(raw, StandardCharsets.UTF_8))) {
            String line;
            int lineNumber = 0;
            while ((line = reader.readLine()) != null) {
                lineNumber++;
                line = line.trim();
                if (line.isEmpty()) {
                    continue;
                }
                JSONObject item;
                try {
                    item = new JSONObject(line);
                } catch (Exception error) {
                    throw new IllegalArgumentException("第 " + lineNumber + " 行不是有效 JSON");
                }
                String kind = item.optString("kind", "");
                if ("meta".equals(kind) || "end".equals(kind)) {
                    continue;
                }
                if ("document".equals(kind)) {
                    String content = item.optString("content", "").trim();
                    if (content.isEmpty()) {
                        skipped++;
                        continue;
                    }
                    String title = normalizedTitle(item.optString("title", "未命名内容"));
                    String key = item.optString("canonical_key", "").trim();
                    if (key.isEmpty()) {
                        key = deterministicKey(content, title);
                    }
                    ExistingDocument existing = findDocumentByKey(key);
                    if (existing != null) {
                        if (existing.deleted) {
                            restoreDocument(existing.id);
                            restored++;
                        } else {
                            skipped++;
                        }
                        continue;
                    }

                    String author = safe(item.optString("author", ""));
                    String mentioned = item.optString("mentioned_books_json", "[]");
                    if (!isJsonArray(mentioned)) {
                        mentioned = "[]";
                    }
                    String date = safe(item.optString("published_at", ""));
                    String sourceType = safe(item.optString("source_type", "导入"));
                    long word = item.optLong("word", compact(content).length());
                    db.execSQL("INSERT INTO documents(" +
                                    "canonical_key,title,title_norm,author,author_norm," +
                                    "content,category,source_type,forum,mname,zname," +
                                    "published_at,source_url,word,hot_score," +
                                    "mentioned_books_json) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                            new Object[]{key, title, compact(title), author, compact(author),
                                    content, safe(item.optString("category", "讨论")),
                                    sourceType, safe(item.optString("forum", "")),
                                    safe(item.optString("mname", "")),
                                    safe(item.optString("zname", "")), date,
                                    safe(item.optString("source_url", "")), word,
                                    item.optLong("hot_score", 0), mentioned});
                    long id = db.compileStatement("SELECT last_insert_rowid()")
                            .simpleQueryForLong();
                    indexDocumentSearch(id, title, author, mentioned);
                    adjustBookIndex(title, mentioned, sourceType, date, id, word, 1);
                    inserted++;
                } else if ("source".equals(kind)) {
                    String documentKey = item.optString("document_key", "");
                    Long documentId = documentIdForKey(documentKey);
                    if (documentId == null) {
                        continue;
                    }
                    String sourceKind = safe(item.optString("source_kind", "导入"));
                    String sourceRef = safe(item.optString("source_ref", ""));
                    String sourceUrl = safe(item.optString("source_url", ""));
                    if (insertSourceIfMissing(documentId, sourceKind, sourceRef, sourceUrl)) {
                        sourcesAdded++;
                    }
                }
            }
            db.setTransactionSuccessful();
        } finally {
            db.endTransaction();
            raw.close();
        }
        return new ImportResult(inserted, restored, skipped, sourcesAdded);
    }

    private void confirmLocalDelete(Document document) {
        if (dataBusy) {
            toast("请等待当前操作完成");
            return;
        }
        new android.app.AlertDialog.Builder(this)
                .setTitle("删除单条扫书？")
                .setMessage("这条内容将从搜索、书库和收藏中隐藏。内置原始数据不会被修改，" +
                        "之后可在“数据”页恢复。")
                .setNegativeButton("取消", null)
                .setPositiveButton("本地删除", (dialog, which) -> {
                    dataBusy = true;
                    toast("正在删除本地记录…");
                    executor.execute(() -> {
                        try {
                            boolean removed = deleteDocumentLocally(document);
                            mainHandler.post(() -> {
                                dataBusy = false;
                                if (removed) {
                                    toast("已从本地资料库删除");
                                    switchTab(detailBackTab);
                                } else {
                                    toast("这条内容已经删除");
                                }
                            });
                        } catch (Exception error) {
                            mainHandler.post(() -> {
                                dataBusy = false;
                                toast("删除失败：" + readableError(error));
                            });
                        }
                    });
                })
                .show();
    }

    private boolean deleteDocumentLocally(Document document) throws Exception {
        db.beginTransaction();
        try {
            db.execSQL("INSERT OR IGNORE INTO local_deleted(document_id,deleted_at) " +
                    "VALUES(?,?)", new Object[]{document.id, isoNow()});
            int changed = db.compileStatement("SELECT changes()").simpleQueryForLong() > 0 ? 1 : 0;
            if (changed == 0) {
                db.setTransactionSuccessful();
                return false;
            }
            db.execSQL("DELETE FROM search_idx WHERE rowid=?",
                    new Object[]{document.id});
            adjustBookIndex(document.title, document.mentionedJson,
                    document.sourceType, document.date, document.id, document.word, -1);
            db.setTransactionSuccessful();
        } finally {
            db.endTransaction();
        }
        removeFavorite(document.id);
        preferences.edit().putString("last_data_message",
                "已在本地删除《" + previewText(document.title, 36) + "》。").apply();
        return true;
    }

    private void confirmRestoreAll() {
        int count = (int) localDeletedCount();
        if (count == 0) {
            return;
        }
        new android.app.AlertDialog.Builder(this)
                .setTitle("恢复全部本地删除？")
                .setMessage("将恢复 " + count + " 条内容，并重新加入搜索、书库和书名聚合。")
                .setNegativeButton("取消", null)
                .setPositiveButton("恢复", (dialog, which) -> {
                    dataBusy = true;
                    updateDataStatus("正在恢复本地删除…");
                    executor.execute(() -> {
                        try {
                            int restored = restoreAllDeleted();
                            finishDataOperation("已恢复 " + restored + " 条本地删除内容。", false);
                        } catch (Exception error) {
                            finishDataOperation("恢复失败：" + readableError(error), true);
                        }
                    });
                })
                .show();
    }

    private int restoreAllDeleted() throws Exception {
        List<Long> ids = new ArrayList<>();
        Cursor cursor = db.rawQuery(
                "SELECT document_id FROM local_deleted ORDER BY deleted_at,rowid", null);
        try {
            while (cursor.moveToNext()) {
                ids.add(cursor.getLong(0));
            }
        } finally {
            cursor.close();
        }
        db.beginTransaction();
        try {
            for (long id : ids) {
                restoreDocument(id);
            }
            db.setTransactionSuccessful();
        } finally {
            db.endTransaction();
        }
        return ids.size();
    }

    private void restoreDocument(long id) {
        Cursor cursor = db.rawQuery("SELECT * FROM documents WHERE id=?",
                new String[]{String.valueOf(id)});
        try {
            if (!cursor.moveToFirst()) {
                db.delete("local_deleted", "document_id=?",
                        new String[]{String.valueOf(id)});
                return;
            }
            Document document = Document.fromCursor(cursor);
            db.delete("local_deleted", "document_id=?",
                    new String[]{String.valueOf(id)});
            indexDocumentSearch(id, document.title, document.author, document.mentionedJson);
            adjustBookIndex(document.title, document.mentionedJson,
                    document.sourceType, document.date, id, document.word, 1);
        } finally {
            cursor.close();
        }
    }

    private void finishDataOperation(String message, boolean error) {
        mainHandler.post(() -> {
            dataBusy = false;
            preferences.edit().putString("last_data_message", message).apply();
            if (currentTab == 4 && !detailOpen) {
                switchTab(4);
            } else if (!error) {
                toast(message);
            }
        });
    }

    private void updateDataStatus(String message) {
        mainHandler.post(() -> {
            if (dataStatus != null) {
                dataStatus.setText(message);
            }
        });
    }

    private long localDocumentCount() {
        return scalarLong("SELECT count(*) FROM documents WHERE id NOT IN " +
                "(SELECT document_id FROM local_deleted)", 0);
    }

    private long localDeletedCount() {
        return scalarLong("SELECT count(*) FROM local_deleted", 0);
    }

    private long localBookCount() {
        return scalarLong("SELECT count(*) FROM books", 0);
    }

    private long visibleSourceCount() {
        return scalarLong("SELECT count(*) FROM document_sources s " +
                "WHERE s.document_id NOT IN (SELECT document_id FROM local_deleted)", 0);
    }

    private long scalarLong(String sql, long fallback) {
        try (Cursor cursor = db.rawQuery(sql, null)) {
            if (cursor.moveToFirst()) {
                return cursor.getLong(0);
            }
        } catch (Exception ignored) {
        }
        return fallback;
    }

    private String metaValue(String key, String fallback) {
        try (Cursor cursor = db.rawQuery("SELECT value FROM meta WHERE key=?",
                new String[]{key})) {
            if (cursor.moveToFirst()) {
                return safe(cursor.getString(0));
            }
        }
        return fallback;
    }

    private String isoNow() {
        SimpleDateFormat format = new SimpleDateFormat(
                "yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.ROOT);
        format.setTimeZone(TimeZone.getTimeZone("UTC"));
        return format.format(new Date());
    }

    @SuppressLint("WrongConstant")
    private void applyLegacyBreakStrategy(TextView view) {
        view.setBreakStrategy(Layout.BREAK_STRATEGY_HIGH_QUALITY);
    }

    private String normalizedTitle(String value) {
        String title = safe(value).replace('\r', ' ').replace('\n', ' ').trim();
        return title.isEmpty() ? "未命名内容" : title;
    }

    private String deterministicKey(String content, String title) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            String body = compact(content);
            String material = body.length() >= 20
                    ? body : compact(title) + "\n" + body;
            byte[] bytes = digest.digest(material.getBytes(StandardCharsets.UTF_8));
            StringBuilder result = new StringBuilder();
            for (byte value : bytes) {
                result.append(String.format(Locale.ROOT, "%02x", value & 0xff));
            }
            return result.toString();
        } catch (Exception ignored) {
            return UUID.nameUUIDFromBytes((title + content)
                    .getBytes(StandardCharsets.UTF_8)).toString();
        }
    }

    private ExistingDocument findDocumentByKey(String canonicalKey) {
        Cursor cursor = db.rawQuery(
                "SELECT d.id, EXISTS(SELECT 1 FROM local_deleted ld " +
                        "WHERE ld.document_id=d.id) AS deleted " +
                        "FROM documents d WHERE d.canonical_key=? LIMIT 1",
                new String[]{canonicalKey});
        try {
            if (cursor.moveToFirst()) {
                return new ExistingDocument(cursor.getLong(0), cursor.getInt(1) != 0);
            }
        } finally {
            cursor.close();
        }
        return null;
    }

    private Long documentIdForKey(String canonicalKey) {
        if (canonicalKey == null || canonicalKey.isEmpty()) {
            return null;
        }
        try (Cursor cursor = db.rawQuery(
                "SELECT id FROM documents WHERE canonical_key=? LIMIT 1",
                new String[]{canonicalKey})) {
            return cursor.moveToFirst() ? cursor.getLong(0) : null;
        }
    }

    private boolean isJsonArray(String value) {
        try {
            new JSONArray(value);
            return true;
        } catch (Exception ignored) {
            return false;
        }
    }

    private void indexDocumentSearch(long id, String title, String author,
                                     String mentionedJson) {
        StringBuilder searchable = new StringBuilder(safe(title)).append(' ')
                .append(safe(author));
        try {
            JSONArray books = new JSONArray(mentionedJson);
            for (int i = 0; i < books.length(); i++) {
                searchable.append(' ').append(books.optString(i, ""));
            }
        } catch (Exception ignored) {
        }
        String tokens = buildFtsQuery(searchable.toString());
        db.execSQL("DELETE FROM search_idx WHERE rowid=?", new Object[]{id});
        db.execSQL("INSERT INTO search_idx(rowid,tokens) VALUES(?,?)",
                new Object[]{id, tokens});
    }

    private boolean insertSourceIfMissing(long documentId, String kind,
                                          String ref, String url) {
        try (Cursor cursor = db.rawQuery(
                "SELECT 1 FROM document_sources WHERE document_id=? " +
                        "AND source_kind=? AND source_ref=? AND source_url=? LIMIT 1",
                new String[]{String.valueOf(documentId), safe(kind),
                        safe(ref), safe(url)})) {
            if (cursor.moveToFirst()) {
                return false;
            }
        }
        db.execSQL("INSERT INTO document_sources(" +
                        "document_id,source_kind,source_ref,source_url) VALUES(?,?,?,?)",
                new Object[]{documentId, safe(kind), safe(ref), safe(url)});
        return true;
    }

    private Map<String, String> candidateBookTitles(String title, String mentionedJson) {
        Map<String, String> candidates = new java.util.LinkedHashMap<>();
        String cleanTitle = normalizedTitle(title).replaceAll("^《|》$", "").trim();
        boolean titleLooksLikePost = cleanTitle.matches(
                ".*(近期|记录|书单|推荐|求书|合集|杂谈|吐槽|楼中楼).*");
        if (cleanTitle.length() >= 2 && cleanTitle.length() <= 80 && !titleLooksLikePost) {
            candidates.put(compact(cleanTitle), cleanTitle);
        }
        try {
            JSONArray books = new JSONArray(mentionedJson);
            for (int i = 0; i < books.length(); i++) {
                String book = normalizedTitle(books.optString(i, ""))
                        .replaceAll("^《|》$", "").trim();
                if (book.length() >= 2 && book.length() <= 80) {
                    String norm = compact(book);
                    if (!candidates.containsKey(norm)) {
                        candidates.put(norm, book);
                    }
                }
            }
        } catch (Exception ignored) {
        }
        return candidates;
    }

    private void adjustBookIndex(String title, String mentionedJson,
                                 String sourceType, String date, long documentId,
                                 long word, int delta) {
        for (Map.Entry<String, String> entry :
                candidateBookTitles(title, mentionedJson).entrySet()) {
            String norm = entry.getKey();
            String display = entry.getValue();
            int exists;
            Cursor check = db.rawQuery(
                    "SELECT 1 FROM books WHERE title_norm=? LIMIT 1",
                    new String[]{norm});
            try {
                exists = check.moveToFirst() ? 1 : 0;
            } finally {
                check.close();
            }
            if (delta > 0) {
                if (exists == 0) {
                    String sources;
                    try {
                        sources = new JSONArray().put(safe(sourceType)).toString();
                    } catch (Exception ignored) {
                        sources = "[]";
                    }
                    db.execSQL("INSERT OR IGNORE INTO books(" +
                                    "title_norm,title,review_count,best_document_id," +
                                    "latest_at,sources_json) VALUES(?,?,?,?,?,?)",
                            new Object[]{norm, display, 1, documentId,
                                    safe(date), sources});
                } else {
                    db.execSQL("UPDATE books SET review_count=review_count+1," +
                                    "latest_at=CASE WHEN latest_at IS NULL OR latest_at<? " +
                                    "THEN ? ELSE latest_at END WHERE title_norm=?",
                            new Object[]{safe(date), safe(date), norm});
                }
            } else {
                if (exists == 0) {
                    continue;
                }
                db.execSQL("UPDATE books SET review_count=review_count-1 " +
                        "WHERE title_norm=?", new Object[]{norm});
                Cursor replacement = db.rawQuery(
                        "SELECT id FROM documents WHERE (title_norm=? OR " +
                                "instr(mentioned_books_json,?)>0) AND id NOT IN " +
                                "(SELECT document_id FROM local_deleted) " +
                                "ORDER BY word DESC,published_at DESC,id DESC LIMIT 1",
                        new String[]{norm, display});
                try {
                    if (replacement.moveToFirst()) {
                        long best = replacement.getLong(0);
                        db.execSQL("UPDATE books SET best_document_id=? " +
                                "WHERE title_norm=?", new Object[]{best, norm});
                    } else {
                        db.execSQL("DELETE FROM books WHERE title_norm=?",
                                new Object[]{norm});
                    }
                } finally {
                    replacement.close();
                }
            }
        }
    }

    private void removeFavorite(long id) {
        Set<String> saved = preferences.getStringSet(
                "favorite_ids", new LinkedHashSet<>());
        Set<String> updated = new LinkedHashSet<>(saved == null
                ? Collections.emptySet() : saved);
        updated.remove(String.valueOf(id));
        preferences.edit().putStringSet("favorite_ids", updated).apply();
    }

    private String readableError(Exception error) {
        String message = error.getMessage();
        return message == null || message.trim().isEmpty()
                ? error.getClass().getSimpleName() : message;
    }

    private List<Document> favoritesDocuments() {
        Set<String> saved = preferences.getStringSet("favorite_ids", new LinkedHashSet<>());
        if (saved == null || saved.isEmpty()) {
            return new ArrayList<>();
        }
        List<String> ids = new ArrayList<>(saved);
        StringBuilder placeholders = new StringBuilder();
        for (int i = 0; i < ids.size(); i++) {
            if (i > 0) {
                placeholders.append(',');
            }
            placeholders.append('?');
        }
        return queryDocuments("SELECT * FROM documents WHERE id IN (" + placeholders +
                ") AND id NOT IN (SELECT document_id FROM local_deleted) " +
                "ORDER BY published_at DESC,id DESC", ids.toArray(new String[0]));
    }

    private void openDocument(long documentId) {
        Document document = loadDocument(documentId);
        if (document == null) {
            toast("没有找到这条内容");
            return;
        }
        if (!detailOpen) {
            detailBackTab = currentTab;
        }
        detailOpen = true;
        currentDetailId = documentId;
        bottomBar.setVisibility(View.GONE);
        content.removeAllViews();

        LinearLayout page = column();
        page.setBackgroundColor(BG);
        page.addView(simpleToolbar("阅读", this::returnFromDetail));

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        LinearLayout article = column();
        article.setPadding(dp(13), dp(13), dp(13), dp(28));
        scroll.addView(article, new ScrollView.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        page.addView(scroll, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));
        content.addView(page);

        LinearLayout headline = column();
        headline.setPadding(dp(17), dp(16), dp(17), dp(16));
        headline.setBackground(gradient(TEAL_DARK, TEAL, 15));
        LinearLayout badgeRow = row();
        badgeRow.setGravity(Gravity.CENTER_VERTICAL);
        TextView badge = text(document.category, 12, TEAL_DEEP, Typeface.BOLD);
        badge.setPadding(dp(10), dp(5), dp(10), dp(5));
        badge.setBackground(round(GOLD, 11));
        badgeRow.addView(badge);
        TextView date = text(document.date.isEmpty() ? "日期未知" : document.date,
                12, Color.argb(220, 255, 255, 255), Typeface.NORMAL);
        date.setPadding(dp(10), 0, 0, 0);
        badgeRow.addView(date, new LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        headline.addView(badgeRow);
        TextView title = text(document.title, 22, Color.WHITE, Typeface.BOLD);
        title.setLineSpacing(0, 1.16f);
        addWithTop(headline, title, 13);
        String author = document.author.isEmpty() ? "作者/发帖人未知" : "作者/发帖人  " + document.author;
        TextView authorView = text(author, 12, Color.argb(218, 255, 255, 255),
                Typeface.NORMAL);
        addWithTop(headline, authorView, 7);
        article.addView(headline);

        LinearLayout actionCard = row();
        actionCard.setPadding(dp(10), dp(11), dp(10), dp(11));
        actionCard.setBackground(round(Color.WHITE, 14));
        actionCard.setElevation(dp(2));
        boolean favored = isFavorite(document.id);
        TextView favorite = actionButton(favored ? "★ 已收藏" : "☆ 收藏",
                favored ? PINK_PALE : TEAL_PALE, favored ? PINK_DARK : TEAL_DARK);
        actionCard.addView(favorite, weightedAction());
        TextView copy = actionButton("复制正文", Color.rgb(239, 244, 243), TEXT);
        actionCard.addView(copy, weightedAction());
        TextView original = actionButton("打开原帖", PINK_PALE, PINK_DARK);
        actionCard.addView(original, weightedAction());
        addWithTop(article, actionCard, 10);

        LinearLayout bodyCard = column();
        bodyCard.setPadding(dp(17), dp(17), dp(17), dp(18));
        bodyCard.setBackground(round(Color.WHITE, 15));
        bodyCard.setElevation(dp(1));
        TextView body = text("", 16, Color.rgb(65, 70, 69), Typeface.NORMAL);
        body.setText(formatScanContent(document.content));
        body.setTextIsSelectable(true);
        body.setLineSpacing(dp(6), 1.52f);
        body.setPadding(0, dp(2), 0, dp(2));
        if (android.os.Build.VERSION.SDK_INT >= 29) {
            body.setBreakStrategy(LineBreaker.BREAK_STRATEGY_HIGH_QUALITY);
        } else {
            applyLegacyBreakStrategy(body);
        }
        bodyCard.addView(body);
        addWithTop(article, bodyCard, 10);

        List<String> mentioned = readMentionedBooks(document.mentionedJson);
        if (!mentioned.isEmpty()) {
            LinearLayout booksCard = column();
            booksCard.setPadding(dp(16), dp(14), dp(16), dp(13));
            booksCard.setBackground(round(Color.WHITE, 14));
            TextView heading = text("文中提及书名", 14, TEXT, Typeface.BOLD);
            booksCard.addView(heading);
            LinearLayout chips = row();
            chips.setPadding(0, dp(8), 0, 0);
            int chipCount = Math.min(8, mentioned.size());
            for (int i = 0; i < chipCount; i++) {
                TextView bookChip = text(mentioned.get(i), 12, TEAL_DARK, Typeface.BOLD);
                bookChip.setPadding(dp(10), dp(6), dp(10), dp(6));
                bookChip.setBackground(round(TEAL_PALE, 11));
                LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
                lp.rightMargin = dp(6);
                lp.bottomMargin = dp(5);
                chips.addView(bookChip, lp);
            }
            booksCard.addView(chips);
            addWithTop(article, booksCard, 10);
        }

        LinearLayout pager = row();
        Document newer = adjacentDocument(document, true);
        Document older = adjacentDocument(document, false);
        TextView previous = actionButton(newer == null ? "‹ 没有上一篇" : "‹ 上一篇",
                Color.WHITE, newer == null ? Color.LTGRAY : TEAL_DARK);
        previous.setEnabled(newer != null);
        if (newer != null) {
            previous.setOnClickListener(v -> openDocument(newer.id));
        }
        pager.addView(previous, weightedAction());
        TextView next = actionButton(older == null ? "下一篇 没有 ›" : "下一篇 ›",
                Color.WHITE, older == null ? Color.LTGRAY : TEAL_DARK);
        next.setEnabled(older != null);
        if (older != null) {
            next.setOnClickListener(v -> openDocument(older.id));
        }
        pager.addView(next, weightedAction());
        addWithTop(article, pager, 10);

        LinearLayout dataActions = row();
        TextView exportSingle = actionButton("导出此条", Color.WHITE, TEAL_DARK);
        exportSingle.setOnClickListener(v -> requestSingleExport(document));
        dataActions.addView(exportSingle, weightedAction());
        TextView deleteLocal = actionButton("删除此条扫书", Color.WHITE, TEAL_DARK);
        deleteLocal.setOnClickListener(v -> confirmLocalDelete(document));
        dataActions.addView(deleteLocal, weightedAction());
        addWithTop(article, dataActions, 9);

        favorite.setOnClickListener(v -> {
            boolean now = toggleFavorite(document.id);
            favorite.setText(now ? "★ 已收藏" : "☆ 收藏");
            favorite.setTextColor(now ? PINK_DARK : TEAL_DARK);
            favorite.setBackground(rippleRound(now ? PINK_PALE : TEAL_PALE,
                    Color.TRANSPARENT, 12, Color.argb(42, 0, 0, 0)));
            toast(now ? "已加入收藏" : "已取消收藏");
        });
        copy.setOnClickListener(v -> copyText(document.content));
        original.setOnClickListener(v -> {
            if (document.sourceUrl.isEmpty()) {
                toast("这条记录没有可打开的原帖链接");
            } else {
                openUrl(document.sourceUrl);
            }
        });
    }

    private LinearLayout.LayoutParams weightedAction() {
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        lp.setMargins(dp(3), 0, dp(3), 0);
        return lp;
    }

    private TextView actionButton(String label, int background, int foreground) {
        TextView button = text(label, 13, foreground, Typeface.BOLD);
        button.setGravity(Gravity.CENTER);
        button.setPadding(dp(8), dp(10), dp(8), dp(10));
        button.setBackground(rippleRound(background, Color.TRANSPARENT, 12,
                Color.argb(42, 0, 0, 0)));
        return button;
    }

    private LinearLayout simpleToolbar(String label, Runnable backAction) {
        LinearLayout bar = row();
        bar.setGravity(Gravity.CENTER_VERTICAL);
        bar.setPadding(dp(8), dp(7), dp(12), dp(7));
        bar.setBackgroundColor(TEAL_DARK);
        TextView back = text("‹", 32, Color.WHITE, Typeface.NORMAL);
        back.setGravity(Gravity.CENTER);
        back.setPadding(dp(5), 0, dp(8), dp(2));
        back.setBackground(rippleRound(Color.TRANSPARENT, Color.TRANSPARENT, 12,
                Color.argb(55, 255, 255, 255)));
        back.setOnClickListener(v -> backAction.run());
        bar.addView(back, new LinearLayout.LayoutParams(dp(45), dp(48)));
        TextView title = text(label, 16, Color.WHITE, Typeface.BOLD);
        bar.addView(title, new LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        TextView archived = text("本地资料库", 11, Color.argb(210, 255, 255, 255),
                Typeface.NORMAL);
        bar.addView(archived);
        return bar;
    }

    private void returnFromDetail() {
        detailOpen = false;
        currentDetailId = -1;
        switchTab(detailBackTab);
    }

    private Document adjacentDocument(Document current, boolean newer) {
        String date = current.date == null ? "" : current.date;
        String sql;
        if (newer) {
            sql = "SELECT * FROM documents WHERE " +
                    "(published_at>? OR (published_at=? AND id<?)) " +
                    "AND id NOT IN (SELECT document_id FROM local_deleted) " +
                    "ORDER BY published_at ASC,id DESC LIMIT 1";
        } else {
            sql = "SELECT * FROM documents WHERE " +
                    "(published_at<? OR (published_at=? AND id>?)) " +
                    "AND id NOT IN (SELECT document_id FROM local_deleted) " +
                    "ORDER BY published_at DESC,id ASC LIMIT 1";
        }
        List<Document> result = queryDocuments(sql,
                new String[]{date, date, String.valueOf(current.id)});
        return result.isEmpty() ? null : result.get(0);
    }

    private boolean toggleFavorite(long id) {
        Set<String> saved = preferences.getStringSet("favorite_ids", new LinkedHashSet<>());
        Set<String> updated = new LinkedHashSet<>(saved == null
                ? Collections.emptySet() : saved);
        String key = String.valueOf(id);
        boolean added;
        if (updated.contains(key)) {
            updated.remove(key);
            added = false;
        } else {
            updated.add(key);
            added = true;
        }
        preferences.edit().putStringSet("favorite_ids", updated).apply();
        return added;
    }

    private boolean isFavorite(long id) {
        Set<String> saved = preferences.getStringSet("favorite_ids", Collections.emptySet());
        return saved != null && saved.contains(String.valueOf(id));
    }

    private void copyText(String content) {
        ClipboardManager manager =
                (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
        manager.setPrimaryClip(ClipData.newPlainText("扫书内容", content));
        toast("正文已复制");
    }

    private void openUrl(String url) {
        try {
            startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url)));
        } catch (Exception error) {
            toast("无法打开链接");
        }
    }

    private void hideKeyboard() {
        View focus = getCurrentFocus();
        if (focus != null) {
            InputMethodManager manager =
                    (InputMethodManager) getSystemService(Context.INPUT_METHOD_SERVICE);
            manager.hideSoftInputFromWindow(focus.getWindowToken(), 0);
        }
    }

    private LinearLayout sectionTitle(String title, String action, View.OnClickListener listener) {
        LinearLayout row = row();
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(0, dp(22), 0, dp(9));
        TextView heading = text(title, 18, TEXT, Typeface.BOLD);
        row.addView(heading, new LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        TextView actionView = text(action + "  ›", 12, PINK_DARK, Typeface.BOLD);
        actionView.setPadding(dp(9), dp(5), 0, dp(5));
        attachPressFeedback(actionView, 10);
        actionView.setOnClickListener(listener);
        row.addView(actionView);
        return row;
    }

    private View documentCard(Document d, int previewLimit, boolean compact) {
        LinearLayout card = column();
        card.setPadding(dp(15), dp(13), dp(15), dp(13));
        card.setBackground(rippleRound(CARD, Color.TRANSPARENT, 15,
                Color.argb(35, 0, 0, 0)));
        card.setElevation(dp(2));
        bindWholeCardClick(card, v -> openDocument(d.id));

        LinearLayout meta = row();
        meta.setGravity(Gravity.CENTER_VERTICAL);
        TextView badge = text(d.category, 11, categoryTextColor(d.category), Typeface.BOLD);
        badge.setPadding(dp(8), dp(4), dp(8), dp(4));
        badge.setBackground(round(categoryPaleColor(d.category), 10));
        meta.addView(badge);
        TextView source = text("  " + d.sourceType +
                        (d.forum.isEmpty() ? "" : " · " + d.forum),
                11, MUTED, Typeface.NORMAL);
        source.setSingleLine(true);
        source.setEllipsize(android.text.TextUtils.TruncateAt.END);
        meta.addView(source, new LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        TextView date = text(d.date.isEmpty() ? "日期未知" : d.date, 11, MUTED,
                Typeface.NORMAL);
        meta.addView(date);
        card.addView(meta);

        TextView title = text(d.title, compact ? 16 : 17, TEXT, Typeface.BOLD);
        title.setLineSpacing(0, 1.18f);
        title.setMaxLines(compact ? 2 : 3);
        title.setEllipsize(android.text.TextUtils.TruncateAt.END);
        addWithTop(card, title, 8);

        if (!compact) {
            String preview = previewText(d.content, previewLimit);
            TextView body = text(preview, 13, Color.rgb(92, 101, 99), Typeface.NORMAL);
            body.setLineSpacing(dp(2), 1.35f);
            body.setMaxLines(3);
            body.setEllipsize(android.text.TextUtils.TruncateAt.END);
            addWithTop(card, body, 7);
        }

        LinearLayout footer = row();
        footer.setGravity(Gravity.CENTER_VERTICAL);
        footer.setPadding(0, dp(8), 0, 0);
        String author = d.author.isEmpty() ? "发帖人未知" : d.author;
        TextView authorView = text(author + "  ·  " + formatCompact(d.word) + " 字",
                11, MUTED, Typeface.NORMAL);
        footer.addView(authorView, new LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        TextView read = text(isFavorite(d.id) ? "★ 已收藏" : "阅读 ›", 12,
                isFavorite(d.id) ? PINK_DARK : TEAL_DARK, Typeface.BOLD);
        footer.addView(read);
        card.addView(footer);
        return card;
    }

    private String previewText(String content, int limit) {
        String text = stripSourceMetadata(content == null ? "" : content)
                .replace("\r", " ")
                .replace("\n", " ")
                .replace("\t", " ")
                .replaceAll(" {2,}", " ")
                .trim();
        if (text.length() <= limit) {
            return text;
        }
        return text.substring(0, limit).trim() + "…";
    }

    private static String stripSourceMetadata(String value) {
        return safe(value)
                .replaceAll("(?m)^\\s*(?:来源|原始来源|合并记录|来源链接)" +
                        "\\s*[:：].*$", "")
                .replaceAll("https?://\\S+", "")
                .replaceAll("\\(@[^\\n)]*#[^\\n)]*\\)", "")
                .trim();
    }

    private List<Document> queryDocuments(String sql, String[] args) {
        List<Document> documents = new ArrayList<>();
        try (Cursor cursor = db.rawQuery(sql, args)) {
            while (cursor.moveToNext()) {
                documents.add(Document.fromCursor(cursor));
            }
        }
        return documents;
    }

    private Document loadDocument(long id) {
        List<Document> found = queryDocuments("SELECT * FROM documents WHERE id=? " +
                        "AND id NOT IN (SELECT document_id FROM local_deleted)",
                new String[]{String.valueOf(id)});
        return found.isEmpty() ? null : found.get(0);
    }

    private List<String> readMentionedBooks(String json) {
        List<String> books = new ArrayList<>();
        try {
            JSONArray array = new JSONArray(json);
            for (int i = 0; i < array.length() && books.size() < 12; i++) {
                String title = array.optString(i, "").trim();
                if (!title.isEmpty()) {
                    books.add(title);
                }
            }
        } catch (Exception ignored) {
        }
        return books;
    }

    private long metaLong(String key, long fallback) {
        Cursor cursor = db.rawQuery("SELECT value FROM meta WHERE key=?",
                new String[]{key});
        try {
            if (cursor.moveToFirst()) {
                return Long.parseLong(cursor.getString(0));
            }
        } catch (Exception ignored) {
        } finally {
            cursor.close();
        }
        return fallback;
    }

    private String buildFtsQuery(String input) {
        LinkedHashSet<String> tokens = new LinkedHashSet<>();
        Matcher matcher = QUERY_CHUNKS.matcher(input.toLowerCase(Locale.ROOT));
        while (matcher.find()) {
            String chunk = matcher.group();
            if (chunk.matches("[\\u4e00-\\u9fff]+")) {
                if (chunk.length() == 1) {
                    tokens.add(chunk);
                } else {
                    for (int i = 0; i < chunk.length() - 1; i++) {
                        tokens.add(chunk.substring(i, i + 2));
                    }
                }
            } else {
                tokens.add(chunk);
            }
        }
        return String.join(" ", tokens);
    }

    private static String compact(String value) {
        if (value == null) {
            return "";
        }
        return value.toLowerCase(Locale.ROOT).replaceAll("[\\p{P}\\p{S}\\s]+", "");
    }

    private static String cleanDisplayTitle(String value) {
        String title = Normalizer.normalize(stripSourceMetadata(safe(value)), Normalizer.Form.NFKC)
                .replace("\r", " ")
                .replace("\n", " ")
                .replace("\u200b", "")
                .trim();
        title = title.replaceAll("\\s*[·•]\\s*楼中楼\\s*$", "");
        title = title.replaceAll("^\\s*(?:回复|楼中楼)\\s*[:：]\\s*", "");
        title = title.replaceAll("^\\s*[（(]?再补档[）)]?\\s*", "");
        title = title.replaceAll("^\\s*【\\s*Time\\s*[:：].*?】\\s*", "");
        title = title.replaceAll("(?i)\\[(?:图片|image)\\]|看高清大图[，,]?\\s*打开贴吧App", "");
        title = title.replaceAll("_20\\d{6}_\\d{6}\\s*$", "");
        title = title.replaceAll("\\s+", " ").trim();
        title = title.replaceAll("\\s+([,，。.!！？:：;；])", "$1");
        title = title.replaceAll("^[\\s·•\\-—_]+|[\\s·•\\-—_]+$", "");
        return title.isEmpty() ? "未命名内容" : title;
    }

    private int categoryTextColor(String category) {
        return TEAL_DARK;
    }

    private int categoryPaleColor(String category) {
        return TEAL_PALE;
    }

    private static String formatCompact(long value) {
        if (value >= 10000) {
            double amount = value / 10000.0;
            return String.format(Locale.CHINA, amount >= 10 ? "%.1f万" : "%.2f万", amount)
                    .replace(".0万", "万");
        }
        return String.format(Locale.CHINA, "%,d", value);
    }

    private LinearLayout column() {
        FeedbackLinearLayout view = new FeedbackLinearLayout(this);
        view.setOrientation(LinearLayout.VERTICAL);
        return view;
    }

    private LinearLayout row() {
        FeedbackLinearLayout view = new FeedbackLinearLayout(this);
        view.setOrientation(LinearLayout.HORIZONTAL);
        return view;
    }

    private TextView text(String value, float size, int color, int style) {
        FeedbackTextView view = new FeedbackTextView(this);
        view.setText(value == null ? "" : value);
        view.setTextSize(size);
        view.setTextColor(color);
        view.setTypeface(Typeface.create("sans", style));
        return view;
    }

    private void addWithTop(LinearLayout parent, View child, int topDp) {
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        params.topMargin = dp(topDp);
        parent.addView(child, params);
    }

    private GradientDrawable round(int color, float radiusDp) {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(color);
        drawable.setCornerRadius(dp(radiusDp));
        return drawable;
    }

    private RippleDrawable rippleRound(int fillColor, int strokeColor,
                                       float radiusDp, int rippleColor) {
        GradientDrawable content = round(fillColor, radiusDp);
        if (strokeColor != Color.TRANSPARENT) {
            content.setStroke(dp(1), strokeColor);
        }
        GradientDrawable mask = round(Color.WHITE, radiusDp);
        return new RippleDrawable(ColorStateList.valueOf(rippleColor), content, mask);
    }

    private void attachPressFeedback(View view, float radiusDp) {
        Drawable content = view.getBackground();
        GradientDrawable mask = round(Color.WHITE, radiusDp);
        view.setBackground(new RippleDrawable(
                ColorStateList.valueOf(Color.argb(42, 0, 0, 0)), content, mask));
        view.setClickable(true);
        view.setFocusable(true);
    }

    private void applyPressFeedback(View view, android.view.MotionEvent event) {
        if (!view.isClickable()) {
            return;
        }
        int action = event.getActionMasked();
        if (action == android.view.MotionEvent.ACTION_DOWN) {
            view.setPressed(true);
            if (preferences.getBoolean("haptic_enabled", false)) {
                view.performHapticFeedback(
                        android.view.HapticFeedbackConstants.CLOCK_TICK);
            }
        } else if (action == android.view.MotionEvent.ACTION_UP
                || action == android.view.MotionEvent.ACTION_CANCEL) {
            view.setPressed(false);
        }
    }

    private void bindWholeCardClick(View root, View.OnClickListener listener) {
        root.setOnClickListener(listener);
        root.setClickable(true);
        root.setFocusable(true);
    }

    private void configureListFeedback(ListView list) {
        StateListDrawable selector = new StateListDrawable();
        selector.addState(new int[]{android.R.attr.state_pressed},
                round((TEAL_DARK & 0x00ffffff) | 0x1c000000, 12));
        selector.addState(new int[]{}, round(Color.TRANSPARENT, 12));
        list.setSelector(selector);
        list.setDrawSelectorOnTop(true);
    }

    private GradientDrawable gradient(int start, int end, float radiusDp) {
        GradientDrawable drawable = new GradientDrawable(
                GradientDrawable.Orientation.TL_BR, new int[]{start, end});
        drawable.setCornerRadius(dp(radiusDp));
        return drawable;
    }

    private int dp(float value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private static String safe(String value) {
        return value == null ? "" : value;
    }

    private void toast(String message) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show();
    }

    @Override
    public void onBackPressed() {
        if (detailOpen) {
            returnFromDetail();
        } else if (currentTab != 0) {
            switchTab(0);
        } else {
            super.onBackPressed();
        }
    }

    @Override
    protected void onDestroy() {
        if (pendingSearch != null) {
            mainHandler.removeCallbacks(pendingSearch);
        }
        executor.shutdownNow();
        if (db != null && db.isOpen()) {
            db.close();
        }
        super.onDestroy();
    }

    private interface ChoiceListener {
        void onSelected(String value);
    }

    private class DocumentAdapter extends BaseAdapter {
        private final List<Document> items;
        private final String query;

        DocumentAdapter(List<Document> items, String query) {
            this.items = items;
            this.query = query;
        }

        @Override
        public int getCount() {
            return items.size();
        }

        @Override
        public Object getItem(int position) {
            return items.get(position);
        }

        @Override
        public long getItemId(int position) {
            return items.get(position).id;
        }

        @Override
        public View getView(int position, View convertView, ViewGroup parent) {
            View view = documentCard(items.get(position), 130, false);
            LinearLayout holder = new LinearLayout(MainActivity.this);
            holder.setPadding(dp(1), dp(5), dp(1), dp(5));
            holder.addView(view, new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
            return holder;
        }
    }

    private class BookAdapter extends BaseAdapter {
        @Override
        public int getCount() {
            return books.size();
        }

        @Override
        public Object getItem(int position) {
            return books.get(position);
        }

        @Override
        public long getItemId(int position) {
            return books.get(position).id;
        }

        @Override
        public View getView(int position, View convertView, ViewGroup parent) {
            Book book = books.get(position);
            LinearLayout outer = new LinearLayout(MainActivity.this);
            outer.setOrientation(LinearLayout.VERTICAL);
            outer.setPadding(dp(1), dp(5), dp(1), dp(5));
            LinearLayout card = row();
            card.setMinimumHeight(dp(70));
            card.setGravity(Gravity.CENTER_VERTICAL);
            card.setPadding(dp(14), dp(13), dp(13), dp(13));
            card.setBackground(rippleRound(Color.WHITE, Color.TRANSPARENT, 14,
                    Color.argb(35, 0, 0, 0)));
            card.setElevation(dp(1));
            bindWholeCardClick(card, v -> showBookDetail(book));

            TextView rank = text(String.valueOf(position + 1), 13,
                    position < 3 ? PINK_DARK : MUTED, Typeface.BOLD);
            rank.setGravity(Gravity.CENTER);
            rank.setBackground(round(position < 3 ? PINK_PALE : TEAL_SOFT, 10));
            card.addView(rank, new LinearLayout.LayoutParams(dp(34), dp(34)));

            LinearLayout info = column();
            info.setPadding(dp(11), 0, 0, 0);
            TextView title = text(book.displayTitle(), 16, TEXT, Typeface.BOLD);
            title.setMaxLines(1);
            title.setEllipsize(android.text.TextUtils.TruncateAt.END);
            info.addView(title);
            TextView meta = text(book.reviewCount + " 条评论 · " +
                    (book.latestAt.isEmpty() ? "日期未知" : book.latestAt) + " · " +
                    book.sourcesText(), 11, MUTED, Typeface.NORMAL);
            meta.setPadding(0, dp(5), 0, 0);
            meta.setSingleLine(true);
            meta.setEllipsize(android.text.TextUtils.TruncateAt.END);
            info.addView(meta);
            card.addView(info, new LinearLayout.LayoutParams(
                    0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
            TextView arrow = text("›", 24, TEAL, Typeface.NORMAL);
            arrow.setGravity(Gravity.CENTER);
            card.addView(arrow, new LinearLayout.LayoutParams(dp(24), dp(38)));
            outer.addView(card, new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT));
            return outer;
        }
    }

    private static class Document {
        final long id;
        final String title;
        final String author;
        final String content;
        final String category;
        final String sourceType;
        final String forum;
        final String date;
        final String sourceUrl;
        final String mentionedJson;
        final long word;

        Document(long id, String title, String author, String content,
                 String category, String sourceType, String forum,
                 String date, String sourceUrl, String mentionedJson, long word) {
            this.id = id;
            this.title = title;
            this.author = author;
            this.content = content;
            this.category = category;
            this.sourceType = sourceType;
            this.forum = forum;
            this.date = date;
            this.sourceUrl = sourceUrl;
            this.mentionedJson = mentionedJson;
            this.word = word;
        }

        static Document fromCursor(Cursor cursor) {
            String content = safe(cursor.getString(cursor.getColumnIndexOrThrow("content")));
            String title = cleanDisplayTitle(
                    cursor.getString(cursor.getColumnIndexOrThrow("title")));
            if ("未命名内容".equals(title) && !content.isEmpty()) {
                String firstLine = stripSourceMetadata(content).split("\\n", 2)[0].trim();
                if (!firstLine.isEmpty()) {
                    title = firstLine.length() > 32
                            ? firstLine.substring(0, 32).trim() + "…" : firstLine;
                }
            }
            return new Document(cursor.getLong(cursor.getColumnIndexOrThrow("id")),
                    title,
                    safe(cursor.getString(cursor.getColumnIndexOrThrow("author"))),
                    content,
                    safe(cursor.getString(cursor.getColumnIndexOrThrow("category"))),
                    safe(cursor.getString(cursor.getColumnIndexOrThrow("source_type"))),
                    safe(cursor.getString(cursor.getColumnIndexOrThrow("forum"))),
                    safe(cursor.getString(cursor.getColumnIndexOrThrow("published_at"))),
                    safe(cursor.getString(cursor.getColumnIndexOrThrow("source_url"))),
                    safe(cursor.getString(cursor.getColumnIndexOrThrow("mentioned_books_json"))),
                    cursor.getLong(cursor.getColumnIndexOrThrow("word")));
        }
    }

    private class FeedbackTextView extends TextView {
        FeedbackTextView(Context context) {
            super(context);
        }

        @Override
        public boolean onTouchEvent(android.view.MotionEvent event) {
            applyPressFeedback(this, event);
            return super.onTouchEvent(event);
        }
    }

    private class FeedbackLinearLayout extends LinearLayout {
        FeedbackLinearLayout(Context context) {
            super(context);
        }

        @Override
        public boolean onTouchEvent(android.view.MotionEvent event) {
            applyPressFeedback(this, event);
            return super.onTouchEvent(event);
        }
    }

    private class NavTabView extends LinearLayout {
        private final int touchSlop;
        private float downX;
        private float downY;
        private boolean moved;

        NavTabView(Context context) {
            super(context);
            touchSlop = ViewConfiguration.get(context).getScaledTouchSlop();
        }

        @Override
        public boolean dispatchTouchEvent(android.view.MotionEvent event) {
            if (!isEnabled()) {
                return false;
            }
            int action = event.getActionMasked();
            if (action == android.view.MotionEvent.ACTION_DOWN) {
                downX = event.getX();
                downY = event.getY();
                moved = false;
                applyPressFeedback(this, event);
                return true;
            }
            if (action == android.view.MotionEvent.ACTION_MOVE) {
                if (Math.abs(event.getX() - downX) > touchSlop
                        || Math.abs(event.getY() - downY) > touchSlop) {
                    moved = true;
                    setPressed(false);
                }
                return true;
            }
            if (action == android.view.MotionEvent.ACTION_UP) {
                setPressed(false);
                if (!moved && event.getX() >= 0 && event.getX() <= getWidth()
                        && event.getY() >= 0 && event.getY() <= getHeight()) {
                    performClick();
                }
                return true;
            }
            if (action == android.view.MotionEvent.ACTION_CANCEL) {
                moved = true;
                setPressed(false);
                return true;
            }
            return true;
        }
    }

    private static class Book {
        final long id;
        final String title;
        final String titleNorm;
        final int reviewCount;
        final long bestDocumentId;
        final String latestAt;
        final String sourcesJson;

        Book(long id, String title, String titleNorm, int reviewCount,
             long bestDocumentId, String latestAt, String sourcesJson) {
            this.id = id;
            this.title = title;
            this.titleNorm = titleNorm;
            this.reviewCount = reviewCount;
            this.bestDocumentId = bestDocumentId;
            this.latestAt = latestAt;
            this.sourcesJson = sourcesJson;
        }

        static Book fromCursor(Cursor cursor) {
            return new Book(cursor.getLong(cursor.getColumnIndexOrThrow("id")),
                    safe(cursor.getString(cursor.getColumnIndexOrThrow("title"))),
                    safe(cursor.getString(cursor.getColumnIndexOrThrow("title_norm"))),
                    cursor.getInt(cursor.getColumnIndexOrThrow("review_count")),
                    cursor.getLong(cursor.getColumnIndexOrThrow("best_document_id")),
                    safe(cursor.getString(cursor.getColumnIndexOrThrow("latest_at"))),
                    safe(cursor.getString(cursor.getColumnIndexOrThrow("sources_json"))));
        }

        String sourcesText() {
            String result = sourcesJson.replace("[\"", "").replace("\"]", "")
                    .replace("\",\"", " / ").replace("\"", "");
            return result.isEmpty() ? "来源未知" : result;
        }

        String displayTitle() {
            return cleanDisplayTitle(title);
        }
    }

    private static class ExportResult {
        final int documents;
        final int sources;

        ExportResult(int documents, int sources) {
            this.documents = documents;
            this.sources = sources;
        }
    }

    private static class ClipboardEntry {
        final String title;
        final String author;
        final String content;

        ClipboardEntry(String title, String author, String content) {
            this.title = title;
            this.author = author;
            this.content = content;
        }
    }

    private static class ImportResult {
        final int inserted;
        final int restored;
        final int skipped;
        final int sources;

        ImportResult(int inserted, int restored, int skipped, int sources) {
            this.inserted = inserted;
            this.restored = restored;
            this.skipped = skipped;
            this.sources = sources;
        }
    }

    private static class UserBackupResult {
        final int favorites;

        UserBackupResult(int favorites) {
            this.favorites = favorites;
        }
    }

    private static class ExistingDocument {
        final long id;
        final boolean deleted;

        ExistingDocument(long id, boolean deleted) {
            this.id = id;
            this.deleted = deleted;
        }
    }

}
