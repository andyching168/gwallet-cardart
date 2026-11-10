package io.github.andyching168.cardart;

import android.app.Activity;
import android.content.Intent;
import android.content.res.AssetManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.view.View;
import android.view.Window;
import android.view.WindowInsets;
import android.webkit.JavascriptInterface;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.widget.Toast;

import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * One-shot card art editor for devices with temporary root (no KernelSU module, no watcher).
 * Hosts the module's WebUI in a WebView and backs its ksu.exec() calls with `su`.
 */
public class MainActivity extends Activity {
    private static final int PICK_IMAGE = 1;
    private static final String[] SCRIPTS = {"lib.sh", "ctl.sh"};

    private WebView web;
    private ValueCallback<Uri[]> pendingPick;
    private final ExecutorService pool = Executors.newFixedThreadPool(4);
    private File scriptDir;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        scriptDir = new File(getFilesDir(), "scripts");
        extractScripts();

        web = new WebView(this);
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setAllowFileAccess(false);
        s.setAllowContentAccess(true);
        web.addJavascriptInterface(new KsuBridge(), "ksu");
        web.addJavascriptInterface(new AppBridge(), "cardart");
        web.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onShowFileChooser(WebView v, ValueCallback<Uri[]> cb, FileChooserParams p) {
                if (pendingPick != null) pendingPick.onReceiveValue(null);
                pendingPick = cb;
                Intent i = new Intent(Intent.ACTION_GET_CONTENT);
                i.addCategory(Intent.CATEGORY_OPENABLE);
                i.setType("image/*");
                startActivityForResult(Intent.createChooser(i, null), PICK_IMAGE);
                return true;
            }
        });
        // keep the page clear of the status / navigation bars (edge-to-edge on API 35).
        // WebView ignores its own padding, so pad a container around it instead.
        android.widget.FrameLayout root = new android.widget.FrameLayout(this);
        root.addView(web);
        root.setOnApplyWindowInsetsListener((v, insets) -> {
            if (Build.VERSION.SDK_INT >= 30) {
                android.graphics.Insets b = insets.getInsets(WindowInsets.Type.systemBars());
                v.setPadding(b.left, b.top, b.right, b.bottom);
            } else {
                v.setPadding(insets.getSystemWindowInsetLeft(), insets.getSystemWindowInsetTop(),
                        insets.getSystemWindowInsetRight(), insets.getSystemWindowInsetBottom());
            }
            return insets;
        });
        setContentView(root);
        web.loadUrl("file:///android_asset/webroot/index.html");
    }

    /** Copy the shell backend out of the APK so root can run it. */
    private void extractScripts() {
        scriptDir.mkdirs();
        AssetManager am = getAssets();
        for (String n : SCRIPTS) {
            try (InputStream in = am.open("scripts/" + n);
                 OutputStream out = new FileOutputStream(new File(scriptDir, n))) {
                byte[] buf = new byte[8192];
                int r;
                while ((r = in.read(buf)) > 0) out.write(buf, 0, r);
            } catch (Exception e) {
                Toast.makeText(this, "extract " + n + ": " + e, Toast.LENGTH_LONG).show();
            }
        }
        scriptDir.setReadable(true, false);
        scriptDir.setExecutable(true, false);
        for (String n : SCRIPTS) new File(scriptDir, n).setReadable(true, false);
    }

    /*
     * Android 11+ hides other apps' /data/data inside an app's own mount namespace, and a root
     * shell started from the app inherits that namespace. Wallet's cache is only visible from the
     * global namespace, so pick the first way of getting there that this su supports.
     */
    private static final String[][] MODES = {
            {"su", "--mount-master"},                       // KernelSU / Magisk
            {"su", "", "exec nsenter -t 1 -m /system/bin/sh\n"}, // other su + toybox nsenter
            {"su", ""},                                     // last resort
    };
    private static volatile int mode = -1;

    private static synchronized int pickMode() {
        if (mode >= 0) return mode;
        String probe = "[ -d /data/data/com.google.android.apps.walletnfcrel ] && [ \"$(id -u)\" = 0 ] && echo ok";
        for (int i = 0; i < MODES.length; i++) {
            Object[] r = run(MODES[i], probe);
            if (((String) r[1]).trim().equals("ok")) return mode = i;
        }
        return 0; // nothing worked (no root yet): don't cache, retry next time
    }

    /** Run one command in a root shell; returns {exitCode, stdout, stderr}. */
    private static Object[] su(String cmd) {
        return run(MODES[pickMode()], cmd);
    }

    private static Object[] run(String[] m, String cmd) {
        try {
            Process p = (m[1].isEmpty() ? new ProcessBuilder(m[0]) : new ProcessBuilder(m[0], m[1])).start();
            ByteArrayOutputStream out = new ByteArrayOutputStream(), err = new ByteArrayOutputStream();
            Thread to = pump(p.getInputStream(), out), te = pump(p.getErrorStream(), err);
            try (OutputStream in = p.getOutputStream()) {
                String pre = m.length > 2 ? m[2] : "";
                in.write((pre + cmd + "\nexit $?\n").getBytes(StandardCharsets.UTF_8));
            }
            int code = p.waitFor();
            to.join();
            te.join();
            return new Object[]{code, out.toString("UTF-8"), err.toString("UTF-8")};
        } catch (Exception e) {
            return new Object[]{127, "", "su: " + e.getMessage()};
        }
    }

    private static Thread pump(InputStream is, ByteArrayOutputStream to) {
        Thread t = new Thread(() -> {
            byte[] buf = new byte[65536];
            int r;
            try {
                while ((r = is.read(buf)) > 0) to.write(buf, 0, r);
            } catch (Exception ignored) {
            }
        });
        t.start();
        return t;
    }

    /** Same shape as KernelSU's WebUI bridge: ksu.exec(cmd, optionsJson, callbackName). */
    class KsuBridge {
        @JavascriptInterface
        public void exec(String cmd, String options, String callback) {
            pool.execute(() -> {
                Object[] r = su(cmd);
                String js = "window[" + JSONObject.quote(callback) + "] && window["
                        + JSONObject.quote(callback) + "](" + r[0] + ","
                        + JSONObject.quote((String) r[1]) + "," + JSONObject.quote((String) r[2]) + ");";
                web.post(() -> web.evaluateJavascript(js, null));
            });
        }

        @JavascriptInterface
        public void toast(String msg) {
            runOnUiThread(() -> Toast.makeText(MainActivity.this, msg, Toast.LENGTH_SHORT).show());
        }
    }

    class AppBridge {
        @JavascriptInterface
        public String modDir() {
            return scriptDir.getAbsolutePath();
        }
    }

    @Override
    protected void onActivityResult(int req, int res, Intent data) {
        if (req == PICK_IMAGE && pendingPick != null) {
            Uri u = (res == RESULT_OK && data != null) ? data.getData() : null;
            pendingPick.onReceiveValue(u == null ? null : new Uri[]{u});
            pendingPick = null;
            return;
        }
        super.onActivityResult(req, res, data);
    }

    @Override
    public void onBackPressed() {
        // close the editor sheet first if it is open
        web.evaluateJavascript("(function(){var e=document.getElementById('editor');"
                + "if(e&&e.classList.contains('open')){e.classList.remove('open');return 1}return 0})()", v -> {
            if (!"1".equals(v)) MainActivity.super.onBackPressed();
        });
    }

    @Override
    protected void onDestroy() {
        pool.shutdownNow();
        super.onDestroy();
    }
}
