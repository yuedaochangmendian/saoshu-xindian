package com.saoshu.xindian;

import android.app.Activity;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
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
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.io.OutputStreamWriter;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
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
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class MainActivity extends Activity {
    private static final int DB_VERSION = 1;
    private static final int REQUEST_EXPORT_DATA = 2201;
    private static final int REQUEST_IMPORT_DATA = 2202;
    private static final int TEAL = Color.rgb(0, 150, 136);
    private static final int TEAL_DARK = Color.rgb(0, 105, 96);
    private static final int TEAL_DEEP = Color.rgb(0, 77, 76);
    private static final int TEAL_PALE = Color.rgb(224, 242, 241);
    private static final int TEAL_SOFT = Color.rgb(242, 249, 248);
    // Legacy names are retained to keep the view code compact; the whole UI is
    // now one teal family, with gold reserved for a few reading accents.
    private static final int PINK = TEAL;
    private static final int PINK_DARK = TEAL_DEEP;
    private static final int PINK_PALE = TEAL_PALE;
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
    private LinearLayout mainColumn;
    private FrameLayout content;
    private LinearLayout bottomBar;
    private final TextView[] navItems = new TextView[5];
    private int currentTab = 0;
    private int detailBackTab = 0;
    private boolean detailOpen = false;
    private long currentDetailId = -1;

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
            boolean available = target.isFile() && target.length() > 150_000_000L;
            if (!available || installedVersion != DB_VERSION) {
                copyDatabase(target);
                preferences.edit().putInt("db_asset_version", DB_VERSION).apply();
            }
            db = SQLiteDatabase.openDatabase(
                    target.getAbsolutePath(), null, SQLiteDatabase.OPEN_READWRITE);
            initializeLocalSchema();
            mainHandler.post(this::showMainShell);
        } catch (Exception error) {
            mainHandler.post(() -> showFatalError(error));
        }
    }

    private void initializeLocalSchema() {
        db.execSQL("CREATE TABLE IF NOT EXISTS local_deleted (" +
                "document_id INTEGER PRIMARY KEY," +
                "deleted_at TEXT NOT NULL)");
    }

    private void copyDatabase(File target) throws Exception {
        File temporary = new File(getFilesDir(), "saoshu.db.installing");
        if (temporary.exists() && !temporary.delete()) {
            throw new IllegalStateException("无法清理上次未完成的数据库文件");
        }
        InputStream input = getAssets().open("saoshu.db");
        FileOutputStream output = new FileOutputStream(temporary);
        byte[] buffer = new byte[1024 * 1024];
        long copied = 0;
        int nextReport = 5;
        try {
            int count;
            while ((count = input.read(buffer)) != -1) {
                output.write(buffer, 0, count);
                copied += count;
                int percent = (int) Math.min(99, copied * 100L / 177_451_008L);
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
            LinearLayout root = new LinearLayout(this);
            root.setOrientation(LinearLayout.VERTICAL);
            root.setBackgroundColor(BG);

            mainColumn = new LinearLayout(this);
            mainColumn.setOrientation(LinearLayout.VERTICAL);
            root.addView(mainColumn, new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

            content = new FrameLayout(this);
            content.setBackgroundColor(BG);
            mainColumn.addView(content, new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

            bottomBar = buildBottomBar();
            mainColumn.addView(bottomBar, new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, dp(68)));
            setContentView(root);
            switchTab(0);
        } catch (Exception error) {
            showFatalError(error);
        }
    }

    private LinearLayout buildBottomBar() {
        LinearLayout bar = new LinearLayout(this);
        bar.setOrientation(LinearLayout.HORIZONTAL);
        bar.setGravity(Gravity.CENTER_VERTICAL);
        bar.setPadding(dp(6), dp(4), dp(6), dp(4));
        bar.setBackgroundColor(PINK_DARK);
        bar.setElevation(dp(10));
        String[] icons = {"⌂", "⌕", "▤", "★", "⇅"};
        String[] labels = {"首页", "搜索", "书库", "收藏", "数据"};
        for (int i = 0; i < 5; i++) {
            final int tab = i;
            TextView item = text(icons[i] + " " + labels[i], 12, Color.WHITE, Typeface.BOLD);
            item.setGravity(Gravity.CENTER);
            item.setClickable(true);
            item.setFocusable(true);
            item.setOnClickListener(v -> switchTab(tab));
            navItems[i] = item;
            LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                    0, ViewGroup.LayoutParams.MATCH_PARENT, 1f);
            params.setMargins(dp(3), 0, dp(3), 0);
            bar.addView(item, params);
        }
        return bar;
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
            navItems[i].setTextColor(i == tab ? PINK_DARK : Color.argb(225, 255, 255, 255));
            navItems[i].setBackground(round(i == tab ? Color.WHITE : Color.TRANSPARENT, 12));
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
        page.setPadding(dp(16), dp(16), dp(16), dp(26));
        scroll.addView(page, new ScrollView.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        LinearLayout hero = column();
        hero.setPadding(dp(20), dp(20), dp(20), dp(18));
        hero.setBackground(gradient(TEAL_DARK, TEAL, 20));
        LinearLayout brandRow = row();
        TextView brand = text("扫书新典", 28, Color.WHITE, Typeface.BOLD);
        brandRow.addView(brand, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        TextView edition = text("离线版  v1.1", 12, Color.WHITE, Typeface.BOLD);
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
        searchCard.setBackground(round(PINK, 15));
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
                chip.setBackground(round(categoryPaleColor(name), 18));
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
        searchButton.setBackground(round(TEAL, 11));
        searchButton.setPadding(dp(17), dp(9), dp(17), dp(9));
        inputRow.addView(searchButton);
        addWithTop(header, inputRow, 13);

        LinearLayout categoryChoices = choiceRow(
                new String[]{"全部类型", "扫书", "推书", "排雷", "讨论", "求书"},
                searchCategory.isEmpty() ? "全部类型" : searchCategory,
                value -> searchCategory = value.equals("全部类型") ? "" : value);
        addWithTop(header, categoryChoices, 11);
        LinearLayout sourceChoices = choiceRow(
                new String[]{"全部来源", "百度贴吧", "雪群推书", "资料库", "文本页面", "丫丫书屋"},
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
        TextView toggle = new TextView(this);
        toggle.setText(searchFullText ? "● 全文" : "○ 标题");
        toggle.setTextSize(12);
        toggle.setGravity(Gravity.CENTER);
        toggle.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        toggle.setTextColor(searchFullText ? Color.WHITE : TEAL_DARK);
        toggle.setPadding(dp(11), dp(6), dp(11), dp(6));
        toggle.setBackground(round(searchFullText ? TEAL : TEAL_PALE, 12));
        resultHeader.addView(toggle);
        page.addView(resultHeader);

        searchList = new ListView(this);
        searchList.setDivider(null);
        searchList.setDividerHeight(0);
        searchList.setClipToPadding(false);
        searchList.setPadding(dp(10), dp(4), dp(10), dp(12));
        searchList.setBackgroundColor(BG);
        page.addView(searchList, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        searchButton.setOnClickListener(v -> launchSearch());
        toggle.setOnClickListener(v -> {
            searchFullText = !searchFullText;
            toggle.setText(searchFullText ? "● 全文" : "○ 标题");
            toggle.setTextColor(searchFullText ? Color.WHITE : TEAL_DARK);
            toggle.setBackground(round(searchFullText ? TEAL : TEAL_PALE, 12));
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
            chip.setBackground(round(option.equals(active[0])
                    ? PINK_DARK : Color.argb(210, 255, 255, 255), 12));
            chip.setOnClickListener(v -> {
                active[0] = option;
                for (int i = 0; i < row.getChildCount(); i++) {
                    TextView child = (TextView) row.getChildAt(i);
                    boolean isActive = child.getText().toString().equals(active[0]);
                    child.setTextColor(isActive ? Color.WHITE : PINK_DARK);
                    child.setBackground(round(isActive
                            ? PINK_DARK : Color.argb(210, 255, 255, 255), 12));
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
        bookList.setDivider(null);
        bookList.setDividerHeight(0);
        bookList.setClipToPadding(false);
        bookList.setPadding(dp(11), dp(8), dp(11), dp(12));
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
        TextView title = text(book.title, 22, Color.WHITE, Typeface.BOLD);
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
            browse.setBackground(round(PINK, 14));
            browse.setOnClickListener(v -> switchTab(1));
            addWithTop(empty, browse, 18);
            page.addView(empty, new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));
        } else {
            ListView list = new ListView(this);
            list.setDivider(null);
            list.setDividerHeight(0);
            list.setPadding(dp(10), 0, dp(10), dp(12));
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
        page.setPadding(0, 0, 0, dp(24));
        scroll.addView(page);

        LinearLayout header = column();
        header.setPadding(dp(17), dp(16), dp(17), dp(16));
        header.setBackground(gradient(TEAL_DEEP, TEAL, 0));
        TextView title = text("本地数据管理", 23, Color.WHITE, Typeface.BOLD);
        header.addView(title);
        TextView subtitle = text("备份、迁移或整理这台设备上的扫书资料", 12,
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
                "导入扫书",
                "选择由本应用导出的 JSONL 文件。按 canonical_key 自动查重，已有内容不会重复写入。",
                "选择导入文件",
                v -> requestDataImport());
        addWithTop(page, importCard, 10);

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

        TextView format = text(
                "导入导出范围包含扫书、推书、排雷、讨论与求书记录。" +
                        "本应用不下载小说正文，只管理已采集的评论与来源信息。",
                11, MUTED, Typeface.NORMAL);
        format.setLineSpacing(0, 1.4f);
        format.setPadding(dp(18), dp(15), dp(18), 0);
        page.addView(format);
        return scroll;
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
        card.setBackground(round(Color.WHITE, 15));
        card.setElevation(dp(2));
        TextView heading = text(title, 17, TEXT, Typeface.BOLD);
        card.addView(heading);
        TextView body = text(description, 12, MUTED, Typeface.NORMAL);
        body.setLineSpacing(0, 1.35f);
        addWithTop(card, body, 7);
        TextView button = actionButton(buttonLabel, TEAL_PALE, TEAL_DARK);
        button.setOnClickListener(dataBusy ? v -> toast("请等待当前操作完成") : listener);
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
                .setTitle("从本地删除？")
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
        return new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX", Locale.ROOT)
                .format(new Date());
    }

    private String normalizedTitle(String value) {
        String title = safe(value).replace('\r', ' ').replace('\n', ' ').trim();
        return title.isEmpty() ? "未命名内容" : title;
    }

    private String deterministicKey(String content, String title) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] bytes = digest.digest((compact(title) + "\n" + compact(content))
                    .getBytes(StandardCharsets.UTF_8));
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
        TextView body = text(document.content, 16, Color.rgb(71, 71, 71), Typeface.NORMAL);
        body.setTextIsSelectable(true);
        body.setLineSpacing(dp(5), 1.5f);
        bodyCard.addView(body);
        addWithTop(article, bodyCard, 10);

        List<Source> sources = loadSources(document.id);
        if (!sources.isEmpty()) {
            LinearLayout sourceCard = column();
            sourceCard.setPadding(dp(16), dp(14), dp(16), dp(13));
            sourceCard.setBackground(round(TEAL_PALE, 14));
            TextView sourceTitle = text("来源与合并记录", 14, TEAL_DEEP, Typeface.BOLD);
            sourceCard.addView(sourceTitle);
            int visibleSources = Math.min(5, sources.size());
            for (int i = 0; i < visibleSources; i++) {
                Source source = sources.get(i);
                String label = "· " + source.kind +
                        (source.ref.isEmpty() ? "" : "  " + source.ref);
                TextView line = text(label, 12, TEAL_DARK, Typeface.NORMAL);
                line.setPadding(0, dp(6), 0, dp(2));
                line.setSingleLine(true);
                line.setEllipsize(android.text.TextUtils.TruncateAt.END);
                if (!source.url.isEmpty()) {
                    final String url = source.url;
                    line.setTextColor(PINK_DARK);
                    line.setOnClickListener(v -> openUrl(url));
                }
                sourceCard.addView(line);
            }
            if (sources.size() > 5) {
                TextView more = text("查看全部 " + sources.size() + " 条来源 ›",
                        12, PINK_DARK, Typeface.BOLD);
                more.setPadding(0, dp(8), 0, 0);
                more.setOnClickListener(v -> showSourcesDialog(sources));
                sourceCard.addView(more);
            }
            addWithTop(article, sourceCard, 10);
        }

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

        TextView deleteLocal = actionButton("本地删除此条", Color.WHITE, TEAL_DARK);
        deleteLocal.setOnClickListener(v -> confirmLocalDelete(document));
        addWithTop(article, deleteLocal, 9);

        favorite.setOnClickListener(v -> {
            boolean now = toggleFavorite(document.id);
            favorite.setText(now ? "★ 已收藏" : "☆ 收藏");
            favorite.setTextColor(now ? PINK_DARK : TEAL_DARK);
            favorite.setBackground(round(now ? PINK_PALE : TEAL_PALE, 12));
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
        button.setBackground(round(background, 12));
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

    private void showSourcesDialog(List<Source> sources) {
        StringBuilder message = new StringBuilder();
        for (int i = 0; i < sources.size(); i++) {
            Source source = sources.get(i);
            if (i > 0) {
                message.append("\n\n");
            }
            message.append(i + 1).append(". ").append(source.kind);
            if (!source.ref.isEmpty()) {
                message.append("\n记录：").append(source.ref);
            }
            if (!source.url.isEmpty()) {
                message.append("\n链接：").append(source.url);
            }
        }
        new android.app.AlertDialog.Builder(this)
                .setTitle("全部来源")
                .setMessage(message.toString())
                .setPositiveButton("关闭", null)
                .show();
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
        actionView.setOnClickListener(listener);
        row.addView(actionView);
        return row;
    }

    private View documentCard(Document d, int previewLimit, boolean compact) {
        LinearLayout card = column();
        card.setPadding(dp(15), dp(13), dp(15), dp(13));
        card.setBackground(round(CARD, 15));
        card.setElevation(dp(2));
        card.setClickable(true);
        card.setFocusable(true);
        card.setOnClickListener(v -> openDocument(d.id));

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
        String text = content == null ? "" : content
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

    private List<Source> loadSources(long documentId) {
        List<Source> sources = new ArrayList<>();
        Cursor cursor = db.rawQuery("SELECT source_kind,source_ref,source_url " +
                        "FROM document_sources WHERE document_id=? ORDER BY id",
                new String[]{String.valueOf(documentId)});
        try {
            while (cursor.moveToNext()) {
                sources.add(new Source(safe(cursor.getString(0)),
                        safe(cursor.getString(1)), safe(cursor.getString(2))));
            }
        } finally {
            cursor.close();
        }
        return sources;
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
        LinearLayout view = new LinearLayout(this);
        view.setOrientation(LinearLayout.VERTICAL);
        return view;
    }

    private LinearLayout row() {
        LinearLayout view = new LinearLayout(this);
        view.setOrientation(LinearLayout.HORIZONTAL);
        return view;
    }

    private TextView text(String value, float size, int color, int style) {
        TextView view = new TextView(this);
        view.setText(value == null ? "" : value);
        view.setTextSize(size);
        view.setTextColor(color);
        view.setTypeface(Typeface.create("sans", style));
        view.setOnClickListener(null);
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
            outer.setPadding(dp(1), dp(5), dp(1), dp(5));
            LinearLayout card = row();
            card.setGravity(Gravity.CENTER_VERTICAL);
            card.setPadding(dp(14), dp(13), dp(13), dp(13));
            card.setBackground(round(Color.WHITE, 14));
            card.setElevation(dp(1));

            TextView rank = text(String.valueOf(position + 1), 13,
                    position < 3 ? PINK_DARK : MUTED, Typeface.BOLD);
            rank.setGravity(Gravity.CENTER);
            rank.setBackground(round(position < 3 ? PINK_PALE : TEAL_SOFT, 10));
            card.addView(rank, new LinearLayout.LayoutParams(dp(34), dp(34)));

            LinearLayout info = column();
            info.setPadding(dp(11), 0, 0, 0);
            TextView title = text(book.title, 16, TEXT, Typeface.BOLD);
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
            outer.addView(card);
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
            return new Document(cursor.getLong(cursor.getColumnIndexOrThrow("id")),
                    safe(cursor.getString(cursor.getColumnIndexOrThrow("title"))),
                    safe(cursor.getString(cursor.getColumnIndexOrThrow("author"))),
                    safe(cursor.getString(cursor.getColumnIndexOrThrow("content"))),
                    safe(cursor.getString(cursor.getColumnIndexOrThrow("category"))),
                    safe(cursor.getString(cursor.getColumnIndexOrThrow("source_type"))),
                    safe(cursor.getString(cursor.getColumnIndexOrThrow("forum"))),
                    safe(cursor.getString(cursor.getColumnIndexOrThrow("published_at"))),
                    safe(cursor.getString(cursor.getColumnIndexOrThrow("source_url"))),
                    safe(cursor.getString(cursor.getColumnIndexOrThrow("mentioned_books_json"))),
                    cursor.getLong(cursor.getColumnIndexOrThrow("word")));
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
    }

    private static class ExportResult {
        final int documents;
        final int sources;

        ExportResult(int documents, int sources) {
            this.documents = documents;
            this.sources = sources;
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

    private static class ExistingDocument {
        final long id;
        final boolean deleted;

        ExistingDocument(long id, boolean deleted) {
            this.id = id;
            this.deleted = deleted;
        }
    }

    private static class Source {
        final String kind;
        final String ref;
        final String url;

        Source(String kind, String ref, String url) {
            this.kind = kind;
            this.ref = ref;
            this.url = url;
        }
    }
}
