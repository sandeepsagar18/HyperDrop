using System;
using System.IO;
using System.IO.Compression;
using System.Drawing;
using System.Windows.Forms;
using System.Threading.Tasks;
using System.Diagnostics;
using Microsoft.Win32;
using System.Runtime.InteropServices;

namespace HyperDropInstaller
{
    static class Program
    {
        [STAThread]
        static void Main(string[] args)
        {
            if (args != null && args.Length > 0)
            {
                foreach (var arg in args)
                {
                    if (arg.Equals("/uninstall", StringComparison.OrdinalIgnoreCase) ||
                        arg.Equals("-uninstall", StringComparison.OrdinalIgnoreCase) ||
                        arg.Equals("/u", StringComparison.OrdinalIgnoreCase))
                    {
                        InstallerForm.PerformUninstall(silent: false);
                        return;
                    }
                    if (arg.Equals("/uninstall-silent", StringComparison.OrdinalIgnoreCase) ||
                        arg.Equals("/clean", StringComparison.OrdinalIgnoreCase))
                    {
                        InstallerForm.PerformUninstall(silent: true);
                        return;
                    }
                }
            }

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new InstallerForm());
        }
    }

    public class InstallerForm : Form
    {
        private ProgressBar progressBar;
        private Label statusLabel;
        private Label titleLabel;
        private Label subtitleLabel;
        private Button installButton;
        private Button cancelButton;
        private CheckBox cbDesktop;
        private CheckBox cbStartMenu;
        private CheckBox cbLaunch;
        private Panel headerPanel;
        private bool isFinished = false;
        private readonly string installDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "HyperDrop");

        public InstallerForm()
        {
            this.Text = "HyperDrop Setup";
            this.Size = new Size(520, 380);
            this.StartPosition = FormStartPosition.CenterScreen;
            this.FormBorderStyle = FormBorderStyle.FixedDialog;
            this.MaximizeBox = false;
            this.BackColor = Color.FromArgb(17, 24, 39);
            this.ForeColor = Color.White;
            this.Font = new Font("Segoe UI", 9.5f, FontStyle.Regular);

            InitControls();
        }

        private void InitControls()
        {
            // Header Panel
            headerPanel = new Panel()
            {
                Dock = DockStyle.Top,
                Height = 85,
                BackColor = Color.FromArgb(7, 13, 24),
                Padding = new Padding(20, 15, 20, 10)
            };

            titleLabel = new Label()
            {
                Text = "HyperDrop — High-Speed File Transfer",
                Font = new Font("Segoe UI", 12.5f, FontStyle.Bold),
                ForeColor = Color.FromArgb(0, 242, 254),
                AutoSize = true,
                Location = new Point(20, 14)
            };

            subtitleLabel = new Label()
            {
                Text = "Install HyperDrop for Windows on your PC",
                Font = new Font("Segoe UI", 9f),
                ForeColor = Color.FromArgb(156, 163, 175),
                AutoSize = true,
                Location = new Point(22, 42)
            };

            headerPanel.Controls.Add(titleLabel);
            headerPanel.Controls.Add(subtitleLabel);
            this.Controls.Add(headerPanel);

            // Body Controls
            statusLabel = new Label()
            {
                Text = "Ready to install HyperDrop on your computer.",
                Location = new Point(25, 105),
                Size = new Size(460, 22),
                ForeColor = Color.FromArgb(229, 231, 235)
            };
            this.Controls.Add(statusLabel);

            progressBar = new ProgressBar()
            {
                Location = new Point(25, 132),
                Size = new Size(455, 22),
                Style = ProgressBarStyle.Continuous,
                Value = 0
            };
            this.Controls.Add(progressBar);

            cbDesktop = new CheckBox()
            {
                Text = "Create Desktop Shortcut",
                Checked = true,
                Location = new Point(25, 175),
                AutoSize = true,
                ForeColor = Color.FromArgb(209, 213, 219)
            };
            this.Controls.Add(cbDesktop);

            cbStartMenu = new CheckBox()
            {
                Text = "Create Start Menu Entry",
                Checked = true,
                Location = new Point(25, 205),
                AutoSize = true,
                ForeColor = Color.FromArgb(209, 213, 219)
            };
            this.Controls.Add(cbStartMenu);

            cbLaunch = new CheckBox()
            {
                Text = "Launch HyperDrop after installation",
                Checked = true,
                Location = new Point(25, 235),
                AutoSize = true,
                ForeColor = Color.FromArgb(209, 213, 219)
            };
            this.Controls.Add(cbLaunch);

            // Bottom Buttons
            installButton = new Button()
            {
                Text = "Install Now",
                Size = new Size(110, 36),
                Location = new Point(250, 285),
                BackColor = Color.FromArgb(0, 242, 254),
                ForeColor = Color.FromArgb(3, 9, 20),
                FlatStyle = FlatStyle.Flat,
                Font = new Font("Segoe UI", 9.5f, FontStyle.Bold),
                Cursor = Cursors.Hand
            };
            installButton.FlatAppearance.BorderSize = 0;
            installButton.Click += async (s, e) => await StartInstallation();
            this.Controls.Add(installButton);

            cancelButton = new Button()
            {
                Text = "Cancel",
                Size = new Size(100, 36),
                Location = new Point(370, 285),
                BackColor = Color.FromArgb(31, 41, 55),
                ForeColor = Color.White,
                FlatStyle = FlatStyle.Flat,
                Cursor = Cursors.Hand
            };
            cancelButton.FlatAppearance.BorderColor = Color.FromArgb(55, 65, 81);
            cancelButton.Click += (s, e) => this.Close();
            this.Controls.Add(cancelButton);
        }

        private string GetSourceDirectory()
        {
            string baseDir = AppDomain.CurrentDomain.BaseDirectory;
            string[] candidates = new string[]
            {
                Path.Combine(baseDir, "Release"),
                baseDir,
                @"D:\HyperDrop\flutter\build\windows\x64\runner\Release",
                Path.Combine(baseDir, "..", "flutter", "build", "windows", "x64", "runner", "Release")
            };

            foreach (var path in candidates)
            {
                if (Directory.Exists(path) && File.Exists(Path.Combine(path, "hyperdrop_flutter.exe")))
                {
                    return Path.GetFullPath(path);
                }
            }
            return @"D:\HyperDrop\flutter\build\windows\x64\runner\Release";
        }

        private async Task StartInstallation()
        {
            if (isFinished)
            {
                if (cbLaunch.Checked)
                {
                    string exePath = Path.Combine(installDir, "hyperdrop_flutter.exe");
                    if (File.Exists(exePath))
                    {
                        var psi = new ProcessStartInfo(exePath)
                        {
                            WorkingDirectory = installDir,
                            UseShellExecute = true
                        };
                        Process.Start(psi);
                    }
                }
                this.Close();
                return;
            }

            installButton.Enabled = false;
            cancelButton.Enabled = false;

            try
            {
                statusLabel.Text = "Creating installation directory...";
                progressBar.Value = 15;
                await Task.Delay(100);

                if (!Directory.Exists(installDir))
                {
                    Directory.CreateDirectory(installDir);
                }

                statusLabel.Text = "Copying program files...";
                progressBar.Value = 35;
                await Task.Delay(150);

                string actualSourceDir = GetSourceDirectory();
                if (Directory.Exists(actualSourceDir))
                {
                    CopyDirectory(actualSourceDir, installDir);
                }
                else
                {
                    throw new Exception("Release source files not found at: " + actualSourceDir);
                }

                // Ensure server, client, node_modules, and silent vbs are copied into installDir
                progressBar.Value = 55;
                statusLabel.Text = "Bundling background engine & assets...";
                await Task.Delay(100);

                string repoRoot = @"D:\HyperDrop";
                if (!Directory.Exists(repoRoot))
                {
                    repoRoot = Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, ".."));
                }

                string[] requiredFolders = new string[] { "server", "client", "node_modules" };
                foreach (var folder in requiredFolders)
                {
                    string targetFolder = Path.Combine(installDir, folder);
                    if (!Directory.Exists(targetFolder))
                    {
                        string sourceFolder = Path.Combine(actualSourceDir, folder);
                        if (!Directory.Exists(sourceFolder) && Directory.Exists(repoRoot))
                        {
                            sourceFolder = Path.Combine(repoRoot, folder);
                        }
                        if (Directory.Exists(sourceFolder))
                        {
                            CopyDirectory(sourceFolder, targetFolder);
                        }
                    }
                }

                // Generate silent background launcher in installDir
                try
                {
                    string vbsPath = Path.Combine(installDir, "Start-Server-Hidden.vbs");
                    string vbsContent = "Set WshShell = CreateObject(\"WScript.Shell\")\r\n" +
                                        "WshShell.CurrentDirectory = \"" + installDir.Replace("\\", "\\\\") + "\"\r\n" +
                                        "WshShell.Run \"node server/index.js\", 0, False\r\n";
                    File.WriteAllText(vbsPath, vbsContent);
                }
                catch { }

                progressBar.Value = 80;
                statusLabel.Text = "Creating shortcuts and registering application...";
                await Task.Delay(150);

                string exePath = Path.Combine(installDir, "hyperdrop_flutter.exe");

                // Desktop shortcut
                if (cbDesktop.Checked)
                {
                    string desktopPath = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
                    CreateShortcut(Path.Combine(desktopPath, "HyperDrop.lnk"), exePath, installDir, "HyperDrop - High Speed File Transfer");
                }

                // Start Menu shortcut
                if (cbStartMenu.Checked)
                {
                    string startMenu = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.StartMenu), "Programs");
                    CreateShortcut(Path.Combine(startMenu, "HyperDrop.lnk"), exePath, installDir, "HyperDrop - High Speed File Transfer");
                }

                // Windows Uninstall Registry Entry
                RegisterUninstall(installDir, exePath);

                progressBar.Value = 100;
                statusLabel.Text = "Installation completed successfully!";
                statusLabel.ForeColor = Color.FromArgb(0, 255, 135);

                installButton.Text = "Finish";
                installButton.Enabled = true;
                cancelButton.Visible = false;
                isFinished = true;
            }
            catch (Exception ex)
            {
                statusLabel.Text = "Error during install: " + ex.Message;
                statusLabel.ForeColor = Color.FromArgb(239, 68, 68);
                installButton.Enabled = true;
                cancelButton.Enabled = true;
            }
        }

        private static void CopyDirectory(string source, string target)
        {
            foreach (string dirPath in Directory.GetDirectories(source, "*", SearchOption.AllDirectories))
            {
                Directory.CreateDirectory(dirPath.Replace(source, target));
            }

            foreach (string newPath in Directory.GetFiles(source, "*.*", SearchOption.AllDirectories))
            {
                File.Copy(newPath, newPath.Replace(source, target), true);
            }
        }

        private static void CreateShortcut(string shortcutPath, string targetPath, string workingDir, string description)
        {
            Type t = Type.GetTypeFromProgID("WScript.Shell");
            dynamic shell = Activator.CreateInstance(t);
            dynamic shortcut = shell.CreateShortcut(shortcutPath);
            shortcut.TargetPath = targetPath;
            shortcut.WorkingDirectory = workingDir;
            shortcut.Description = description;
            shortcut.Save();
        }

        public static void PerformUninstall(bool silent = false)
        {
            string installPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "HyperDrop");

            try
            {
                // 1. Terminate any running HyperDrop processes
                foreach (var proc in Process.GetProcessesByName("hyperdrop_flutter"))
                {
                    try { proc.Kill(); proc.WaitForExit(1000); } catch { }
                }

                // 2. Remove Shortcuts
                string desktopShortcut = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "HyperDrop.lnk");
                if (File.Exists(desktopShortcut))
                {
                    try { File.Delete(desktopShortcut); } catch { }
                }

                string startMenuShortcut = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.StartMenu), "Programs", "HyperDrop.lnk");
                if (File.Exists(startMenuShortcut))
                {
                    try { File.Delete(startMenuShortcut); } catch { }
                }

                // 3. Remove Registry Uninstall Key
                try
                {
                    Registry.CurrentUser.DeleteSubKeyTree(@"Software\Microsoft\Windows\CurrentVersion\Uninstall\HyperDrop", false);
                }
                catch { }

                // 4. Clean up installation folder via delayed background deletion
                if (Directory.Exists(installPath))
                {
                    var psi = new ProcessStartInfo("cmd.exe", "/c ping 127.0.0.1 -n 2 > nul & rmdir /s /q \"" + installPath + "\"")
                    {
                        CreateNoWindow = true,
                        UseShellExecute = false,
                        WindowStyle = ProcessWindowStyle.Hidden
                    };
                    Process.Start(psi);
                }

                if (!silent)
                {
                    MessageBox.Show("HyperDrop has been successfully uninstalled from your computer.", "HyperDrop Uninstall", MessageBoxButtons.OK, MessageBoxIcon.Information);
                }
            }
            catch (Exception ex)
            {
                if (!silent)
                {
                    MessageBox.Show("Uninstall error: " + ex.Message, "HyperDrop Uninstall", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }
        }

        private static void RegisterUninstall(string installPath, string exePath)
        {
            try
            {
                // Copy installer as uninstaller binary
                string currentExe = Process.GetCurrentProcess().MainModule.FileName;
                string uninstallerPath = Path.Combine(installPath, "Uninstall.exe");
                if (File.Exists(currentExe) && !currentExe.Equals(uninstallerPath, StringComparison.OrdinalIgnoreCase))
                {
                    try { File.Copy(currentExe, uninstallerPath, true); } catch { }
                }

                string uninstallCommand = File.Exists(uninstallerPath)
                    ? "\"" + uninstallerPath + "\" /uninstall"
                    : "powershell.exe -NoProfile -WindowStyle Hidden -Command \"Remove-Item -Path '" + installPath + "' -Recurse -Force\"";

                using (RegistryKey key = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Uninstall\HyperDrop"))
                {
                    if (key != null)
                    {
                        key.SetValue("DisplayName", "HyperDrop");
                        key.SetValue("DisplayVersion", "2.0.0");
                        key.SetValue("Publisher", "HyperDrop Team");
                        key.SetValue("DisplayIcon", exePath);
                        key.SetValue("InstallLocation", installPath);
                        key.SetValue("UninstallString", uninstallCommand);
                        key.SetValue("NoModify", 1, RegistryValueKind.DWord);
                        key.SetValue("NoRepair", 1, RegistryValueKind.DWord);
                    }
                }
            }
            catch { }
        }
    }
}
