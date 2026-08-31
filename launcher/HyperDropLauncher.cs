using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Runtime.InteropServices;
using System.Threading;

namespace HyperDropLauncher
{
    static class Program
    {
        [DllImport("user32.dll")]
        private static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

        private const int SW_RESTORE = 9;

        [STAThread]
        static void Main()
        {
            string appDir = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\');

            // 1. Check for running instance window
            IntPtr existingHwnd = FindWindow("FLUTTER_RUNNER_WIN32_WINDOW", "HyperDrop");
            if (existingHwnd != IntPtr.Zero)
            {
                ShowWindow(existingHwnd, SW_RESTORE);
                SetForegroundWindow(existingHwnd);
                return;
            }

            // 2. Start Node server silently in background
            StartNodeServer(appDir);

            // 3. Launch App Window
            LaunchAppWindow(appDir);
        }

        static void StartNodeServer(string appDir)
        {
            if (IsServerAlive()) return;

            string nodeExe = Path.Combine(appDir, "node.exe");
            string serverJs = Path.Combine(appDir, "server", "index.js");

            if (!File.Exists(nodeExe)) nodeExe = "node";
            if (!File.Exists(serverJs))
            {
                serverJs = Path.Combine(appDir, "..", "server", "index.js");
            }

            if (File.Exists(serverJs))
            {
                try
                {
                    var psi = new ProcessStartInfo
                    {
                        FileName = nodeExe,
                        Arguments = "\"" + serverJs + "\"",
                        WorkingDirectory = appDir,
                        WindowStyle = ProcessWindowStyle.Hidden,
                        CreateNoWindow = true,
                        UseShellExecute = false
                    };
                    Process.Start(psi);
                }
                catch { }
            }

            for (int i = 0; i < 10; i++)
            {
                Thread.Sleep(300);
                if (IsServerAlive()) break;
            }
        }

        static bool IsServerAlive()
        {
            try
            {
                var req = (HttpWebRequest)WebRequest.Create("http://127.0.0.1:3000/api/status");
                req.Timeout = 800;
                using (var res = (HttpWebResponse)req.GetResponse())
                {
                    return res.StatusCode == HttpStatusCode.OK;
                }
            }
            catch
            {
                return false;
            }
        }

        static void LaunchAppWindow(string appDir)
        {
            string flutterExe = Path.Combine(appDir, "hyperdrop_flutter.exe");

            // Attempt 1: Native Flutter App Window
            if (File.Exists(flutterExe))
            {
                try
                {
                    var psi = new ProcessStartInfo
                    {
                        FileName = flutterExe,
                        WorkingDirectory = appDir,
                        UseShellExecute = true
                    };
                    var p = Process.Start(psi);
                    if (p != null)
                    {
                        Thread.Sleep(800);
                        if (!p.HasExited)
                        {
                            return;
                        }
                    }
                }
                catch { }
            }

            // Attempt 2: Dedicated Windows Native App Mode (Borderless app container, no URL bar, no browser chrome)
            string edgeExe = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Microsoft", "Edge", "Application", "msedge.exe");
            if (!File.Exists(edgeExe))
            {
                edgeExe = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Microsoft", "Edge", "Application", "msedge.exe");
            }

            if (File.Exists(edgeExe))
            {
                try
                {
                    var psi = new ProcessStartInfo
                    {
                        FileName = edgeExe,
                        Arguments = "--app=\"http://127.0.0.1:3000\" --window-size=1280,750 --app-id=HyperDrop",
                        UseShellExecute = true
                    };
                    Process.Start(psi);
                    return;
                }
                catch { }
            }

            // Attempt 3: Chrome App Mode
            string chromeExe = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Google", "Chrome", "Application", "chrome.exe");
            if (!File.Exists(chromeExe))
            {
                chromeExe = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Google", "Chrome", "Application", "chrome.exe");
            }

            if (File.Exists(chromeExe))
            {
                try
                {
                    var psi = new ProcessStartInfo
                    {
                        FileName = chromeExe,
                        Arguments = "--app=\"http://127.0.0.1:3000\" --window-size=1280,750",
                        UseShellExecute = true
                    };
                    Process.Start(psi);
                    return;
                }
                catch { }
            }

            // Fallback: Default system browser
            try
            {
                Process.Start(new ProcessStartInfo("http://127.0.0.1:3000") { UseShellExecute = true });
            }
            catch { }
        }
    }
}
