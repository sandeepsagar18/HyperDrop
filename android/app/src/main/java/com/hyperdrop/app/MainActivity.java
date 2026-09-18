package com.hyperdrop.app;

import android.Manifest;
import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.provider.MediaStore;
import android.view.View;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Toast;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import java.io.File;

import android.app.DownloadManager;
import android.content.Context;
import android.content.SharedPreferences;
import android.net.DhcpInfo;
import android.net.wifi.WifiManager;
import android.webkit.DownloadListener;
import android.webkit.JavascriptInterface;
import android.webkit.URLUtil;

import java.net.HttpURLConnection;
import java.net.URL;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;

public class MainActivity extends AppCompatActivity {

    private WebView webView;
    private ValueCallback<Uri[]> uploadMessage;
    private final static int FILE_CHOOSER_RESULT_CODE = 1001;
    private final static int PERMISSION_REQ_CODE = 1002;
    private SharedPreferences prefs;
    private String currentActiveServer = null;
    private final AtomicBoolean isScanning = new AtomicBoolean(false);
    private final ExecutorService scanPool = Executors.newFixedThreadPool(25);
    private WifiManager.LocalOnlyHotspotReservation hotspotReservation = null;
    private LocalHyperDropServer localServer = null;

    public class AndroidBridge {
        @JavascriptInterface
        public String getDeviceIp() {
            return getLocalIpAddress();
        }

        @JavascriptInterface
        public void setServerIp(String ip) {
            if (ip != null && !ip.trim().isEmpty()) {
                final String targetUrl = "http://" + ip.trim().replace("http://", "").replace("/", "") + ":3000";
                new Thread(() -> {
                    if (isServerReachable(targetUrl + "/api/status")) {
                        applyActiveServer(targetUrl);
                    } else {
                        runOnUiThread(() -> Toast.makeText(MainActivity.this, "Cannot reach " + targetUrl, Toast.LENGTH_SHORT).show());
                    }
                }).start();
            }
        }

        @JavascriptInterface
        public void scanNetwork() {
            startDynamicSubnetScan();
        }

        @JavascriptInterface
        public void saveBase64File(String base64Data, String fileName) {
            new Thread(() -> {
                try {
                    byte[] bytes = android.util.Base64.decode(base64Data, android.util.Base64.DEFAULT);
                    File downloadDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS);
                    if (!downloadDir.exists()) downloadDir.mkdirs();
                    File dest = new File(downloadDir, fileName);
                    java.io.FileOutputStream fos = new java.io.FileOutputStream(dest);
                    fos.write(bytes);
                    fos.flush();
                    fos.close();

                    android.media.MediaScannerConnection.scanFile(
                        MainActivity.this,
                        new String[]{dest.getAbsolutePath()},
                        null,
                        null
                    );

                    runOnUiThread(() -> Toast.makeText(MainActivity.this, "✓ Saved " + fileName + " to Downloads", Toast.LENGTH_SHORT).show());
                } catch (Exception e) {
                    runOnUiThread(() -> Toast.makeText(MainActivity.this, "Error saving: " + e.getMessage(), Toast.LENGTH_SHORT).show());
                }
            }).start();
        }

        @JavascriptInterface
        public void startDirectHotspot() {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WifiManager wifiManager = (WifiManager) getApplicationContext().getSystemService(Context.WIFI_SERVICE);
                if (wifiManager != null) {
                    runOnUiThread(() -> {
                        try {
                            wifiManager.startLocalOnlyHotspot(new WifiManager.LocalOnlyHotspotCallback() {
                                @Override
                                public void onStarted(WifiManager.LocalOnlyHotspotReservation reservation) {
                                    super.onStarted(reservation);
                                    hotspotReservation = reservation;
                                    String ssid = "";
                                    String password = "";
                                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && reservation.getSoftApConfiguration() != null) {
                                        ssid = reservation.getSoftApConfiguration().getSsid();
                                        password = reservation.getSoftApConfiguration().getPassphrase();
                                    } else if (reservation.getWifiConfiguration() != null) {
                                        ssid = reservation.getWifiConfiguration().SSID;
                                        password = reservation.getWifiConfiguration().preSharedKey;
                                    }
                                    final String finalSsid = ssid != null ? ssid : "HyperDrop-Direct";
                                    final String finalPassword = password != null ? password : "";
                                    runOnUiThread(() -> {
                                        Toast.makeText(MainActivity.this, "⚡ 5GHz Direct Hotspot Active!", Toast.LENGTH_SHORT).show();
                                        if (webView != null) {
                                            webView.evaluateJavascript(
                                                "if (window.app && window.app.onHotspotStarted) { " +
                                                "  window.app.onHotspotStarted('" + finalSsid + "', '" + finalPassword + "'); " +
                                                "}", null);
                                        }
                                    });
                                }

                                @Override
                                public void onStopped() {
                                    super.onStopped();
                                    hotspotReservation = null;
                                    runOnUiThread(() -> {
                                        if (webView != null) {
                                            webView.evaluateJavascript("if (window.app && window.app.onHotspotStopped) { window.app.onHotspotStopped(); }", null);
                                        }
                                    });
                                }

                                @Override
                                public void onFailed(int reason) {
                                    super.onFailed(reason);
                                    runOnUiThread(() -> Toast.makeText(MainActivity.this, "Hotspot start failed (code: " + reason + ")", Toast.LENGTH_LONG).show());
                                }
                            }, null);
                        } catch (Exception e) {
                            Toast.makeText(MainActivity.this, "Hotspot error: " + e.getMessage(), Toast.LENGTH_SHORT).show();
                        }
                    });
                }
            } else {
                runOnUiThread(() -> Toast.makeText(MainActivity.this, "Hotspot requires Android 8.0+", Toast.LENGTH_SHORT).show());
            }
        }

        @JavascriptInterface
        public void stopDirectHotspot() {
            if (hotspotReservation != null) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    hotspotReservation.close();
                }
                hotspotReservation = null;
                runOnUiThread(() -> Toast.makeText(MainActivity.this, "Direct Hotspot Stopped", Toast.LENGTH_SHORT).show());
            }
        }

        @JavascriptInterface
        public int getWifiLinkSpeed() {
            try {
                WifiManager wifi = (WifiManager) getApplicationContext().getSystemService(Context.WIFI_SERVICE);
                if (wifi != null && wifi.getConnectionInfo() != null) {
                    return wifi.getConnectionInfo().getLinkSpeed();
                }
            } catch (Exception ignored) {}
            return 0;
        }

        @JavascriptInterface
        public int getWifiFrequency() {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    WifiManager wifi = (WifiManager) getApplicationContext().getSystemService(Context.WIFI_SERVICE);
                    if (wifi != null && wifi.getConnectionInfo() != null) {
                        return wifi.getConnectionInfo().getFrequency();
                    }
                }
            } catch (Exception ignored) {}
            return 0;
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        prefs = getSharedPreferences("hyperdrop_prefs", MODE_PRIVATE);

        // Keep screen on during active transfers and app usage
        getWindow().addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        webView = new WebView(this);
        setContentView(webView);

        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(true);
        settings.setAllowFileAccess(true);
        settings.setAllowContentAccess(true);
        settings.setAllowFileAccessFromFileURLs(true);
        settings.setAllowUniversalAccessFromFileURLs(true);
        settings.setLoadWithOverviewMode(true);
        settings.setUseWideViewPort(true);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);

        webView.addJavascriptInterface(new AndroidBridge(), "AndroidBridge");

        webView.setDownloadListener(new DownloadListener() {
            @Override
            public void onDownloadStart(String url, String userAgent, String contentDisposition, String mimetype, long contentLength) {
                try {
                    DownloadManager.Request request = new DownloadManager.Request(Uri.parse(url));
                    request.setMimeType(mimetype);
                    String fileName = URLUtil.guessFileName(url, contentDisposition, mimetype);
                    request.setTitle(fileName);
                    request.setDescription("Downloading file via HyperDrop...");
                    request.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED);
                    request.setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, fileName);

                    DownloadManager dm = (DownloadManager) getSystemService(DOWNLOAD_SERVICE);
                    if (dm != null) {
                        dm.enqueue(request);
                        Toast.makeText(MainActivity.this, "📥 Downloading " + fileName + " to Downloads", Toast.LENGTH_SHORT).show();
                    }
                } catch (Exception e) {
                    try {
                        Intent intent = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
                        startActivity(intent);
                    } catch (Exception ex) {
                        Toast.makeText(MainActivity.this, "Download failed: " + e.getMessage(), Toast.LENGTH_SHORT).show();
                    }
                }
            }
        });

        webView.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                return false;
            }

            @Override
            public void onPageFinished(WebView view, String url) {
                super.onPageFinished(view, url);
                applyActiveServer("http://127.0.0.1:3000");
                startDynamicSubnetScan();
            }
        });

        webView.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onShowFileChooser(WebView webView, ValueCallback<Uri[]> filePathCallback, FileChooserParams fileChooserParams) {
                if (uploadMessage != null) {
                    uploadMessage.onReceiveValue(null);
                }
                uploadMessage = filePathCallback;

                Intent intent = fileChooserParams.createIntent();
                intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true);
                try {
                    startActivityForResult(Intent.createChooser(intent, "Select Files to Send"), FILE_CHOOSER_RESULT_CODE);
                } catch (Exception e) {
                    uploadMessage = null;
                    Toast.makeText(MainActivity.this, "Cannot open file chooser", Toast.LENGTH_SHORT).show();
                    return false;
                }
                return true;
            }
        });

        requestNecessaryPermissions();

        // Start autonomous local embedded server for standalone Phone-to-Phone transfers
        try {
            localServer = new LocalHyperDropServer(this, 3000);
            localServer.start();
        } catch (Exception e) {
            android.util.Log.e("MainActivity", "Embedded server init error: " + e.getMessage());
        }

        // Load fast local web assets embedded directly in APK
        webView.loadUrl("file:///android_asset/web/index.html");

        // Start continuous smart discovery daemon
        startContinuousDiscoveryDaemon();
    }

    private void startContinuousDiscoveryDaemon() {
        new Thread(() -> {
            int consecutiveFailures = 0;
            while (!isFinishing()) {
                if (currentActiveServer != null) {
                    if (isServerReachable(currentActiveServer + "/api/status")) {
                        consecutiveFailures = 0;
                    } else {
                        consecutiveFailures++;
                    }
                }
                
                if (currentActiveServer == null || consecutiveFailures >= 3) {
                    startDynamicSubnetScan();
                }
                try {
                    Thread.sleep(4000);
                } catch (InterruptedException ignored) {}
            }
        }).start();
    }

    private void startDynamicSubnetScan() {
        if (!isScanning.compareAndSet(false, true)) {
            return;
        }

        new Thread(() -> {
            try {
                List<String> priorityIps = new ArrayList<>();

                // 1. Last remembered server
                String lastSaved = prefs.getString("last_server_ip", null);
                if (lastSaved != null) priorityIps.add(lastSaved);

                // 2. Gateway from WiFi DHCP
                String gatewayIp = getGatewayIp();
                if (gatewayIp != null && !priorityIps.contains(gatewayIp)) {
                    priorityIps.add(gatewayIp);
                }

                // 3. Known static IPs / hotspots
                String[] standardIps = { "192.168.29.137", "192.168.137.1", "192.168.43.1", "192.168.1.1", "192.168.0.1", "10.0.0.1" };
                for (String sip : standardIps) {
                    if (!priorityIps.contains(sip)) priorityIps.add(sip);
                }

                // Fast check priority targets first
                for (String ip : priorityIps) {
                    String candidate = "http://" + ip + ":3000";
                    if (isServerReachable(candidate + "/api/status")) {
                        applyActiveServer(candidate);
                        isScanning.set(false);
                        return;
                    }
                }

                // 4. Full /24 Subnet Scan using local device IP prefix
                String localIp = getLocalIpAddress();
                if (localIp != null && localIp.contains(".")) {
                    String prefix = localIp.substring(0, localIp.lastIndexOf('.') + 1);
                    final AtomicBoolean found = new AtomicBoolean(false);

                    for (int i = 1; i <= 254; i++) {
                        if (found.get()) break;
                        final String scanIp = prefix + i;
                        if (priorityIps.contains(scanIp)) continue;

                        scanPool.execute(() -> {
                            if (found.get()) return;
                            String url = "http://" + scanIp + ":3000";
                            if (isServerReachable(url + "/api/status")) {
                                if (found.compareAndSet(false, true)) {
                                    applyActiveServer(url);
                                }
                            }
                        });
                    }
                }

                // 5. Ultimate Fallback: Local Autonomous Embedded Server
                if (currentActiveServer == null && isServerReachable("http://127.0.0.1:3000/api/status")) {
                    applyActiveServer("http://127.0.0.1:3000");
                }
            } catch (Exception ignored) {
            } finally {
                isScanning.set(false);
            }
        }).start();
    }

    private void applyActiveServer(String activeServer) {
        if (activeServer == null) return;
        boolean isSameServer = activeServer.equals(currentActiveServer);
        currentActiveServer = activeServer;
        String rawIp = activeServer.replace("http://", "").split(":")[0];
        prefs.edit().putString("last_server_ip", rawIp).apply();

        if (!isSameServer) {
            runOnUiThread(() -> {
                injectServerUrl(activeServer);
                Toast.makeText(MainActivity.this, "⚡ Connected to HyperDrop: " + rawIp, Toast.LENGTH_SHORT).show();
            });
        }
    }

    private void injectServerUrl(String activeServer) {
        if (webView != null) {
            webView.evaluateJavascript(
                "if (window.app) { " +
                "  window.app.serverBaseUrl = '" + activeServer + "'; " +
                "  window.app.initWebSocket(); " +
                "  window.app.fetchPeers(); " +
                "  window.app.fetchVaultItems(); " +
                "}",
                null
            );
        }
    }

    private String getGatewayIp() {
        try {
            WifiManager wifi = (WifiManager) getApplicationContext().getSystemService(Context.WIFI_SERVICE);
            if (wifi != null) {
                DhcpInfo dhcp = wifi.getDhcpInfo();
                if (dhcp != null && dhcp.gateway != 0) {
                    return String.format("%d.%d.%d.%d",
                        (dhcp.gateway & 0xff),
                        (dhcp.gateway >> 8 & 0xff),
                        (dhcp.gateway >> 16 & 0xff),
                        (dhcp.gateway >> 24 & 0xff));
                }
            }
        } catch (Exception ignored) {}
        return null;
    }

    private String getLocalIpAddress() {
        try {
            WifiManager wifi = (WifiManager) getApplicationContext().getSystemService(Context.WIFI_SERVICE);
            if (wifi != null) {
                int ip = wifi.getConnectionInfo().getIpAddress();
                if (ip != 0) {
                    return String.format("%d.%d.%d.%d",
                        (ip & 0xff),
                        (ip >> 8 & 0xff),
                        (ip >> 16 & 0xff),
                        (ip >> 24 & 0xff));
                }
            }
        } catch (Exception ignored) {}
        return null;
    }

    private boolean isServerReachable(String targetUrl) {
        try {
            URL url = new URL(targetUrl);
            HttpURLConnection conn = (HttpURLConnection) url.openConnection();
            conn.setConnectTimeout(2500);
            conn.setReadTimeout(2500);
            conn.setRequestMethod("GET");
            int code = conn.getResponseCode();
            return (code >= 200 && code < 400);
        } catch (Exception e) {
            return false;
        }
    }

    private void requestNecessaryPermissions() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            String[] perms = {
                Manifest.permission.READ_MEDIA_IMAGES,
                Manifest.permission.READ_MEDIA_VIDEO,
                Manifest.permission.READ_MEDIA_AUDIO,
                Manifest.permission.CAMERA
            };
            ActivityCompat.requestPermissions(this, perms, PERMISSION_REQ_CODE);
        } else {
            String[] perms = {
                Manifest.permission.READ_EXTERNAL_STORAGE,
                Manifest.permission.WRITE_EXTERNAL_STORAGE,
                Manifest.permission.CAMERA
            };
            ActivityCompat.requestPermissions(this, perms, PERMISSION_REQ_CODE);
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, @Nullable Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == FILE_CHOOSER_RESULT_CODE) {
            if (uploadMessage == null) return;

            Uri[] results = null;
            if (resultCode == Activity.RESULT_OK && data != null) {
                if (data.getClipData() != null) {
                    int count = data.getClipData().getItemCount();
                    results = new Uri[count];
                    for (int i = 0; i < count; i++) {
                        results[i] = data.getClipData().getItemAt(i).getUri();
                    }
                } else if (data.getData() != null) {
                    results = new Uri[]{data.getData()};
                }
            }
            uploadMessage.onReceiveValue(results);
            uploadMessage = null;
        }
    }

    @Override
    public void onBackPressed() {
        if (webView != null && webView.canGoBack()) {
            webView.goBack();
        } else {
            super.onBackPressed();
        }
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        if (localServer != null) {
            localServer.stop();
            localServer = null;
        }
    }
}
