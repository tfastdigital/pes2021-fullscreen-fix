using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;
using System.Net;
using System.Threading.Tasks;
using System.Text.RegularExpressions;

[assembly: AssemblyTitle("PES 2021 Fullscreen Fix")]
[assembly: AssemblyDescription("Fullscreen, focus and GPU fixer for eFootball PES 2021.")]
[assembly: AssemblyProduct("PES 2021 Fullscreen Fix")]
[assembly: AssemblyCompany("TFast Digital")]
[assembly: AssemblyCopyright("(c) TFast Digital - tfastdigital.com")]
[assembly: AssemblyTrademark("TFast Digital")]
[assembly: AssemblyVersion("1.1.0.0")]
[assembly: AssemblyFileVersion("1.1.0.0")]

namespace TFastDigital
{
    internal static class Brand
    {
        public const string Agency = "TFast Digital";
        public const string Site = "https://tfastdigital.com";
        public const string Telegram = "https://t.me/tfasthub";
        public const string WhatsApp = "https://whatsapp.com/channel/0029VaAYznPK5cDIXJa9nW1a";
        public const string TikTok = "https://www.tiktok.com/@tfasthub";
        public const string YouTube = "https://www.youtube.com/@TfastDigital";
        public const string Version  = "1.1.0";

        // Static file served by GitHub Pages, updated with every release.
        public const string VersionFeed = "https://tfastdigital6.github.io/pes2021-fullscreen-fix/version.json";
        public const string ReleasesPage = "https://github.com/tfastdigital6/pes2021-fullscreen-fix/releases/latest";

        // Neutral greys with a single accent colour.
        public static readonly Color Window = Color.FromArgb(24, 25, 29);
        public static readonly Color Header = Color.FromArgb(31, 33, 38);
        public static readonly Color Panel = Color.FromArgb(38, 40, 46);
        public static readonly Color PanelHigh = Color.FromArgb(48, 51, 58);
        public static readonly Color Border = Color.FromArgb(58, 61, 70);
        public static readonly Color Accent = Color.FromArgb(45, 108, 223);
        public static readonly Color AccentHi = Color.FromArgb(66, 129, 244);
        public static readonly Color Text = Color.FromArgb(230, 232, 236);
        public static readonly Color Muted = Color.FromArgb(150, 155, 166);
        public static readonly Color Faint = Color.FromArgb(112, 117, 128);
        public static readonly Color Ok = Color.FromArgb(107, 190, 130);
        public static readonly Color Warn = Color.FromArgb(214, 178, 92);
        public static readonly Color Fail = Color.FromArgb(214, 110, 110);
        public static readonly Color LogBg = Color.FromArgb(19, 20, 24);
    }

    internal static class Shapes
    {
        public static GraphicsPath Round(RectangleF r, float radius)
        {
            GraphicsPath p = new GraphicsPath();
            if (radius <= 0f) { p.AddRectangle(r); return p; }
            float d = radius * 2f;
            p.AddArc(r.X, r.Y, d, d, 180, 90);
            p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure();
            return p;
        }
    }

    /// <summary>Square, flat button with a hairline border.</summary>
    internal class FlatButton : Button
    {
        private bool _hover;
        private bool _down;

        public Color Fill { get; set; }
        public Color FillHover { get; set; }
        public Color BorderColor { get; set; }
        public int Corner { get; set; }

        public FlatButton()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            FlatStyle = FlatStyle.Flat;
            FlatAppearance.BorderSize = 0;
            Fill = Brand.Panel;
            FillHover = Brand.PanelHigh;
            BorderColor = Brand.Border;
            Corner = 3;
            ForeColor = Brand.Text;
            Cursor = Cursors.Hand;
            Font = new Font("Segoe UI", 9f, FontStyle.Regular);
            TabStop = true;
        }

        protected override void OnMouseEnter(EventArgs e) { _hover = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { _hover = false; _down = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnMouseDown(MouseEventArgs e) { _down = true; Invalidate(); base.OnMouseDown(e); }
        protected override void OnMouseUp(MouseEventArgs e) { _down = false; Invalidate(); base.OnMouseUp(e); }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(Parent != null ? Parent.BackColor : Brand.Window);

            RectangleF r = new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f);
            Color fill = !Enabled ? Color.FromArgb(34, 36, 41) : (_hover ? FillHover : Fill);
            if (_down && Enabled) fill = ControlPaint.Dark(fill, 0.06f);

            using (GraphicsPath path = Shapes.Round(r, Corner))
            {
                using (SolidBrush b = new SolidBrush(fill)) g.FillPath(b, path);
                if (Focused && ShowFocusCues)
                {
                    using (Pen p = new Pen(Brand.Accent, 1.4f)) g.DrawPath(p, path);
                }
                else
                {
                    using (Pen p = new Pen(Enabled ? BorderColor : Color.FromArgb(44, 46, 52), 1f))
                        g.DrawPath(p, path);
                }
            }

            TextRenderer.DrawText(g, Text, Font,
                new Rectangle(6, 0, Width - 12, Height),
                Enabled ? ForeColor : Brand.Faint,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter |
                TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
        }
    }

    /// <summary>Icon button that paints a brand mark instead of text.</summary>
    internal class IconButton : Button
    {
        private bool _hover;
        public string BrandKey { get; set; }

        public IconButton()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            FlatStyle = FlatStyle.Flat;
            FlatAppearance.BorderSize = 0;
            BackColor = Color.Transparent;
            Cursor = Cursors.Hand;
            TabStop = true;
        }

        protected override void OnMouseEnter(EventArgs e) { _hover = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { _hover = false; Invalidate(); base.OnMouseLeave(e); }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(Parent != null ? Parent.BackColor : Brand.Window);

            if (_hover)
            {
                using (GraphicsPath p = Shapes.Round(new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f), 4f))
                using (SolidBrush b = new SolidBrush(Brand.PanelHigh))
                using (Pen pen = new Pen(Brand.Border, 1f))
                {
                    g.FillPath(b, p);
                    g.DrawPath(pen, p);
                }
            }

            float size = Math.Min(Width, Height) - 14f;
            RectangleF glyph = new RectangleF((Width - size) / 2f, (Height - size) / 2f, size, size);
            BrandIcons.Draw(g, BrandKey, glyph);
        }
    }

    /// <summary>Brand marks drawn as vectors; no font or image dependencies.</summary>
    internal static class BrandIcons
    {
        public static void Draw(Graphics g, string key, RectangleF r)
        {
            SmoothingMode old = g.SmoothingMode;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            try
            {
                switch (key)
                {
                    case "telegram": Telegram(g, r); break;
                    case "whatsapp": WhatsApp(g, r); break;
                    case "tiktok": TikTok(g, r); break;
                    case "youtube": YouTube(g, r); break;
                    default: Web(g, r); break;
                }
            }
            finally { g.SmoothingMode = old; }
        }

        private static void Telegram(Graphics g, RectangleF r)
        {
            using (SolidBrush blue = new SolidBrush(Color.FromArgb(34, 158, 217)))
                g.FillEllipse(blue, r);

            PointF[] plane = new PointF[]
            {
                new PointF(r.Left + r.Width * 0.21f, r.Top + r.Height * 0.53f),
                new PointF(r.Left + r.Width * 0.80f, r.Top + r.Height * 0.24f),
                new PointF(r.Left + r.Width * 0.58f, r.Top + r.Height * 0.78f),
                new PointF(r.Left + r.Width * 0.47f, r.Top + r.Height * 0.585f)
            };
            using (SolidBrush white = new SolidBrush(Color.White))
                g.FillPolygon(white, plane);
        }

        private static void WhatsApp(Graphics g, RectangleF r)
        {
            using (SolidBrush green = new SolidBrush(Color.FromArgb(37, 211, 102)))
                g.FillEllipse(green, r);

            // Handset: thick diagonal stroke with round caps plus a bulb at each end.
            float w = r.Width * 0.135f;
            PointF a = new PointF(r.Left + r.Width * 0.34f, r.Top + r.Height * 0.30f);
            PointF b = new PointF(r.Left + r.Width * 0.66f, r.Top + r.Height * 0.62f);

            using (Pen pen = new Pen(Color.White, w))
            {
                pen.StartCap = LineCap.Round;
                pen.EndCap = LineCap.Round;
                g.DrawLine(pen, a, b);
            }
            using (SolidBrush white = new SolidBrush(Color.White))
            {
                float d = r.Width * 0.215f;
                g.FillEllipse(white, a.X - d / 2f, a.Y - d / 2f, d, d);
                g.FillEllipse(white, b.X - d / 2f, b.Y - d / 2f, d, d);
            }
        }

        private static void TikTok(Graphics g, RectangleF r)
        {
            using (GraphicsPath tile = Shapes.Round(r, r.Width * 0.22f))
            using (SolidBrush bg = new SolidBrush(Color.FromArgb(16, 17, 20)))
            using (Pen edge = new Pen(Color.FromArgb(48, 50, 58), 1f))
            {
                g.FillPath(bg, tile);
                g.DrawPath(edge, tile);
            }

            Note(g, r, Color.FromArgb(37, 244, 238), -1.4f, -1.4f);
            Note(g, r, Color.FromArgb(254, 44, 85), 1.4f, 1.4f);
            Note(g, r, Color.White, 0f, 0f);
        }

        private static void Note(Graphics g, RectangleF r, Color colour, float dx, float dy)
        {
            using (SolidBrush b = new SolidBrush(colour))
            {
                g.FillEllipse(b,
                    r.Left + r.Width * 0.20f + dx,
                    r.Top + r.Height * 0.60f + dy,
                    r.Width * 0.30f, r.Height * 0.26f);

                g.FillRectangle(b,
                    r.Left + r.Width * 0.44f + dx,
                    r.Top + r.Height * 0.22f + dy,
                    r.Width * 0.115f, r.Height * 0.42f);

                PointF[] flag = new PointF[]
                {
                    new PointF(r.Left + r.Width * 0.555f + dx, r.Top + r.Height * 0.22f + dy),
                    new PointF(r.Left + r.Width * 0.780f + dx, r.Top + r.Height * 0.29f + dy),
                    new PointF(r.Left + r.Width * 0.720f + dx, r.Top + r.Height * 0.43f + dy),
                    new PointF(r.Left + r.Width * 0.555f + dx, r.Top + r.Height * 0.37f + dy)
                };
                g.FillPolygon(b, flag);
            }
        }

        private static void YouTube(Graphics g, RectangleF r)
        {
            using (GraphicsPath body = Shapes.Round(r, r.Height * 0.28f))
            using (SolidBrush red = new SolidBrush(Color.FromArgb(255, 0, 0)))
                g.FillPath(red, body);

            PointF[] play = new PointF[]
            {
                new PointF(r.Left + r.Width * 0.40f, r.Top + r.Height * 0.28f),
                new PointF(r.Left + r.Width * 0.73f, r.Top + r.Height * 0.50f),
                new PointF(r.Left + r.Width * 0.40f, r.Top + r.Height * 0.72f)
            };
            using (SolidBrush white = new SolidBrush(Color.White))
                g.FillPolygon(white, play);
        }

        private static void Web(Graphics g, RectangleF r)
        {
            float pad = r.Width * 0.12f;
            RectangleF outer = new RectangleF(r.Left + pad, r.Top + pad, r.Width - pad * 2f, r.Height - pad * 2f);

            using (Pen pen = new Pen(Brand.Muted, 1.5f))
            {
                g.DrawEllipse(pen, outer);
                g.DrawEllipse(pen, new RectangleF(
                    outer.Left + outer.Width * 0.30f, outer.Top,
                    outer.Width * 0.40f, outer.Height));
                g.DrawLine(pen, outer.Left, outer.Top + outer.Height * 0.5f,
                                outer.Right, outer.Top + outer.Height * 0.5f);
            }
        }
    }

    /// <summary>Result of an update check.</summary>
    internal sealed class UpdateResult
    {
        public bool Succeeded;
        public bool UpdateAvailable;
        public string LatestVersion = "";
        public string DownloadUrl = "";
        public string Notes = "";
    }

    /// <summary>
    /// Reads the static version feed published on GitHub Pages and compares it with the running
    /// build. Deliberately passive: it only reports, never downloads or executes anything.
    /// </summary>
    internal static class Updater
    {
        private const int TimeoutMs = 6000;

        public static UpdateResult Check()
        {
            UpdateResult result = new UpdateResult();
            string json = null;

            // The feed location can be overridden so the update path is testable without
            // touching the published URL. Not documented as a user option on purpose.
            string feed = Environment.GetEnvironmentVariable("PESFIX_VERSION_FEED");
            if (string.IsNullOrEmpty(feed)) feed = Brand.VersionFeed;

            try
            {
                // .NET Framework 4.x defaults to TLS 1.0; GitHub Pages requires 1.2+.
                try { ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072; } catch { }

                using (WebClient client = new WebClient())
                {
                    client.Headers[HttpRequestHeader.UserAgent] =
                        "PES2021FullscreenFix/" + Brand.Version + " (Windows)";
                    client.Headers[HttpRequestHeader.Accept] = "application/json";
                    client.Proxy = WebRequest.DefaultWebProxy;

                    Task<string> fetch = client.DownloadStringTaskAsync(new Uri(feed));
                    if (!fetch.Wait(TimeoutMs)) return result;
                    json = fetch.Result;
                }
            }
            catch
            {
                // Offline, blocked or GitHub Pages unavailable: stay silent and keep working.
                return result;
            }

            if (string.IsNullOrEmpty(json)) return result;

            string latest = Field(json, "version");
            if (latest.Length == 0) return result;

            result.Succeeded = true;
            result.LatestVersion = latest;
            result.DownloadUrl = Field(json, "url");
            result.Notes = Field(json, "notes");
            if (result.DownloadUrl.Length == 0) result.DownloadUrl = Brand.ReleasesPage;

            result.UpdateAvailable = CompareVersions(latest, Brand.Version) > 0;
            return result;
        }

        private static string Field(string json, string name)
        {
            Match m = Regex.Match(json, "\"" + name + "\"\\s*:\\s*\"([^\"]*)\"", RegexOptions.IgnoreCase);
            return m.Success ? m.Groups[1].Value.Trim() : string.Empty;
        }

        /// <summary>Returns 1 when a is newer than b, -1 when older, 0 when equal.</summary>
        private static int CompareVersions(string a, string b)
        {
            int[] left = Parts(a);
            int[] right = Parts(b);
            for (int i = 0; i < 3; i++)
            {
                if (left[i] > right[i]) return 1;
                if (left[i] < right[i]) return -1;
            }
            return 0;
        }

        private static int[] Parts(string value)
        {
            int[] parts = new int[3];
            string[] split = (value ?? string.Empty).TrimStart('v', 'V').Split('.');
            for (int i = 0; i < 3 && i < split.Length; i++)
            {
                int n;
                if (int.TryParse(split[i], out n)) parts[i] = n;
            }
            return parts;
        }
    }

    internal sealed class HeaderPanel : Panel
    {
        public Icon AppIcon { get; set; }

        public HeaderPanel()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            BackColor = Brand.Header;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.Clear(Brand.Header);

            const int iconSize = 32;
            const int x = 20;
            int y = (Height - iconSize) / 2 - 6;

            if (AppIcon != null)
            {
                g.DrawIcon(AppIcon, new Rectangle(x, y, iconSize, iconSize));
            }
            else
            {
                using (SolidBrush b = new SolidBrush(Brand.Accent))
                    g.FillRectangle(b, new Rectangle(x, y, iconSize, iconSize));
            }

            int textX = x + iconSize + 14;
            using (Font title = new Font("Segoe UI", 12f, FontStyle.Bold))
            using (Font sub = new Font("Segoe UI", 8.5f, FontStyle.Regular))
            using (SolidBrush ink = new SolidBrush(Brand.Text))
            using (SolidBrush soft = new SolidBrush(Brand.Muted))
            {
                g.DrawString("PES 2021 Fullscreen Fix", title, ink, textX, y - 1);
                g.DrawString(Brand.Agency + "   |   " + Brand.Site + "   |   v" + Brand.Version,
                             sub, soft, textX + 1, y + 20);
            }

            using (SolidBrush line = new SolidBrush(Brand.Border))
                g.FillRectangle(line, 0, Height - 1, Width, 1);
        }
    }

    internal sealed class MainForm : Form
    {
        private const string ScriptResource = "PES2021-Fullscreen.ps1";

        private readonly string _gameDir;
        private readonly ToolTip _tips = new ToolTip();

        private FlatButton _play, _install, _gpu, _diagnose, _overlays, _restore, _folder, _stop;
        private RichTextBox _log;
        private Label _status;
        private ProgressBar _progress;
        private Panel _updateBar;
        private Label _updateText;
        private FlatButton _updateAction;
        private Process _current;
        private bool _running;
        private bool _logFrameAdded;
        private readonly bool _noUpdateCheck;

        public MainForm(string gameDir, bool noUpdateCheck)
        {
            _gameDir = gameDir;
            _noUpdateCheck = noUpdateCheck;
            BuildUi();

            if (!string.IsNullOrEmpty(_gameDir))
            {
                Status("Ready.  Game folder: " + _gameDir, false);
                Log("PES 2021 Fullscreen Fix " + Brand.Version);
                Log("Game folder: " + _gameDir);
                Log("");
            }
            else
            {
                Status("PES2021.exe was not found next to this program.", true);
                Log("PES2021.exe was not found next to this program.");
                Log("Place this program in the folder that contains PES2021.exe, or run it with:");
                Log("    -GameDir \"D:\\path\\to\\game\"");
                SetActionsEnabled(false);
                _folder.Enabled = true;
            }
        }

        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            if (!_noUpdateCheck) StartUpdateCheck();
        }

        private void StartUpdateCheck()
        {
            Task.Factory.StartNew(delegate { return Updater.Check(); })
                .ContinueWith(delegate (Task<UpdateResult> t)
                {
                    if (t.Status != TaskStatus.RanToCompletion) return;
                    UpdateResult result = t.Result;
                    if (result.Succeeded && result.UpdateAvailable)
                    {
                        try { BeginInvoke(new Action<UpdateResult>(ShowUpdateBar), result); }
                        catch { }
                    }
                });
        }

        private void ShowUpdateBar(UpdateResult result)
        {
            if (_updateBar == null) return;

            string notes = result.Notes.Length > 0 ? " - " + result.Notes : string.Empty;
            _updateText.Text = "Version " + result.LatestVersion + " is available" + notes;
            _updateText.Tag = result.DownloadUrl;
            _updateBar.Visible = true;
            Log("");
            Log("A newer version is available: " + result.LatestVersion + notes);
            Log("Download: " + result.DownloadUrl);
        }

        // ------------------------------------------------------------------ layout
        private void BuildUi()
        {
            SuspendLayout();

            Text = "PES 2021 Fullscreen Fix - " + Brand.Agency;
            BackColor = Brand.Window;
            ForeColor = Brand.Text;
            StartPosition = FormStartPosition.CenterScreen;
            FormBorderStyle = FormBorderStyle.FixedSingle;
            MaximizeBox = false;
            ClientSize = new Size(720, 666);
            Font = new Font("Segoe UI", 9f);
            AutoScaleMode = AutoScaleMode.None;
            DoubleBuffered = true;

            HeaderPanel header = new HeaderPanel();
            header.AppIcon = LoadAppIcon();
            header.Location = new Point(0, 0);
            header.Size = new Size(ClientSize.Width, 84);
            Controls.Add(header);

            const int pad = 20;
            int w = ClientSize.Width - (pad * 2);

            _play = new FlatButton();
            _play.Text = "Play PES 2021";
            _play.Location = new Point(pad, 100);
            _play.Size = new Size(w, 46);
            _play.Font = new Font("Segoe UI", 10.5f, FontStyle.Bold);
            _play.Fill = Brand.Accent;
            _play.FillHover = Brand.AccentHi;
            _play.BorderColor = Color.FromArgb(30, 84, 180);
            _play.ForeColor = Color.White;
            _play.Corner = 3;
            _play.Click += delegate { RunEngine(new string[] { "-Action", "Play" }, "Play", false); };
            _tips.SetToolTip(_play, "Apply the fix, start the game and keep it fullscreen");
            Controls.Add(_play);

            const int gap = 10;
            int bw = (w - (gap * 2)) / 3;
            const int row1 = 158;
            const int row2 = 206;

            _install = Secondary("Install fix", pad, row1, bw, "Also start the watchdog with Windows");
            _gpu = Secondary("High-performance GPU", pad + bw + gap, row1, bw, "Detect GPUs, force the discrete one and verify it");
            _diagnose = Secondary("Diagnose focus", pad + ((bw + gap) * 2), row1, bw, "Find the program that keeps stealing focus");
            _overlays = Secondary("Close overlays", pad, row2, bw, "Close ScreenRec, Game Bar and GPU overlays");
            _restore = Secondary("Restore all", pad + bw + gap, row2, bw, "Undo every change made by this program");
            _folder = Secondary("Open game folder", pad + ((bw + gap) * 2), row2, bw, "Open the game folder");

            _install.Click += delegate { RunEngine(new string[] { "-Action", "Fix", "-InstallStartup" }, "Install fix", false); };
            _gpu.Click += delegate { RunEngine(new string[] { "-Action", "Gpu" }, "High-performance GPU", false); };
            _diagnose.Click += delegate { RunEngine(new string[] { "-Action", "Diagnose", "-DiagnoseSeconds", "120" }, "Diagnose focus", false); };
            _overlays.Click += delegate { RunEngine(new string[] { "-Action", "Overlays" }, "Close overlays", false); };
            _restore.Click += delegate { ConfirmRestore(); };
            _folder.Click += delegate { OpenGameFolder(); };

            _status = new Label();
            _status.Location = new Point(pad, 260);
            _status.Size = new Size(w - 84, 18);
            _status.AutoEllipsis = true;
            _status.ForeColor = Brand.Muted;
            _status.Text = "Ready";
            Controls.Add(_status);

            _stop = new FlatButton();
            _stop.Text = "Stop";
            _stop.Location = new Point(pad + w - 74, 256);
            _stop.Size = new Size(74, 24);
            _stop.Font = new Font("Segoe UI", 8.5f);
            _stop.Enabled = false;
            _stop.Click += delegate { StopEngine(); };
            Controls.Add(_stop);

            _progress = new ProgressBar();
            _progress.Style = ProgressBarStyle.Marquee;
            _progress.MarqueeAnimationSpeed = 0;
            _progress.Location = new Point(pad, 284);
            _progress.Size = new Size(w, 3);
            _progress.Visible = false;
            Controls.Add(_progress);

            _log = new RichTextBox();
            _log.Location = new Point(pad, 296);
            _log.Size = new Size(w, 188);
            _log.BackColor = Brand.LogBg;
            _log.ForeColor = Brand.Text;
            _log.BorderStyle = BorderStyle.None;
            _log.Font = new Font("Consolas", 8.75f);
            _log.ReadOnly = true;
            _log.WordWrap = true;
            _log.ScrollBars = RichTextBoxScrollBars.None;   // the system scrollbar is light-themed
            _log.HideSelection = true;
            _log.DetectUrls = false;
            _log.TabStop = false;
            Controls.Add(_log);
            _log.HandleCreated += delegate { AddLogFrame(); };

            BuildSocialRow(pad, 496, w);

            // Update notice. Space is reserved so showing it never shifts other controls.
            _updateBar = new Panel();
            _updateBar.Location = new Point(pad, 590);
            _updateBar.Size = new Size(w, 30);
            _updateBar.BackColor = Color.FromArgb(33, 40, 54);
            _updateBar.Visible = false;
            Controls.Add(_updateBar);

            _updateText = new Label();
            _updateText.Location = new Point(10, 7);
            _updateText.Size = new Size(w - 124, 17);
            _updateText.AutoEllipsis = true;
            _updateText.ForeColor = Color.FromArgb(174, 199, 238);
            _updateText.Font = new Font("Segoe UI", 8.5f);
            _updateText.BackColor = Color.Transparent;
            _updateBar.Controls.Add(_updateText);

            _updateAction = new FlatButton();
            _updateAction.Text = "Download";
            _updateAction.Location = new Point(w - 108, 3);
            _updateAction.Size = new Size(100, 24);
            _updateAction.Font = new Font("Segoe UI", 8f);
            _updateAction.Corner = 3;
            _updateAction.BackColor = Color.Transparent;
            _updateAction.Click += delegate
            {
                string url = _updateText.Tag as string;
                OpenUrl(string.IsNullOrEmpty(url) ? Brand.ReleasesPage : url);
            };
            _updateBar.Controls.Add(_updateAction);

            Label foot = new Label();
            foot.Text = Brand.Agency + "   |   " + Brand.Site;
            foot.Location = new Point(pad, 636);
            foot.Size = new Size(w, 18);
            foot.ForeColor = Brand.Faint;
            foot.Font = new Font("Segoe UI", 8f);
            foot.TextAlign = ContentAlignment.MiddleCenter;
            Controls.Add(foot);

            AcceptButton = _play;
            ResumeLayout(false);
        }

        private FlatButton Secondary(string text, int x, int y, int w, string tip)
        {
            FlatButton b = new FlatButton();
            b.Text = text;
            b.Location = new Point(x, y);
            b.Size = new Size(w, 40);
            _tips.SetToolTip(b, tip);
            Controls.Add(b);
            return b;
        }

        private void BuildSocialRow(int pad, int top, int width)
        {
            string[] keys = new string[] { "website", "telegram", "whatsapp", "tiktok", "youtube" };
            string[] labels = new string[] { "Website", "Telegram", "WhatsApp", "TikTok", "YouTube" };
            string[] urls = new string[] { Brand.Site, Brand.Telegram, Brand.WhatsApp, Brand.TikTok, Brand.YouTube };

            const int btn = 40;
            const int colGap = 26;
            int total = keys.Length * btn + (keys.Length - 1) * colGap;
            int startX = pad + (width - total) / 2;

            Panel rule = new Panel();
            rule.Location = new Point(pad, top - 16);
            rule.Size = new Size(width, 1);
            rule.BackColor = Brand.Border;
            Controls.Add(rule);

            for (int i = 0; i < keys.Length; i++)
            {
                IconButton b = new IconButton();
                b.BrandKey = keys[i];
                b.Location = new Point(startX + i * (btn + colGap), top);
                b.Size = new Size(btn, btn);
                string url = urls[i];
                b.Click += delegate { OpenUrl(url); };
                _tips.SetToolTip(b, urls[i]);
                Controls.Add(b);

                Label cap = new Label();
                cap.Text = labels[i];
                cap.Location = new Point(b.Left - 13, top + btn + 1);
                cap.Size = new Size(btn + 26, 15);
                cap.ForeColor = Brand.Faint;
                cap.Font = new Font("Segoe UI", 7.5f);
                cap.TextAlign = ContentAlignment.MiddleCenter;
                cap.AutoSize = false;
                Controls.Add(cap);
            }
        }

        private void AddLogFrame()
        {
            if (_logFrameAdded) return;
            _logFrameAdded = true;

            Panel frame = new Panel();
            frame.Location = new Point(_log.Left - 1, _log.Top - 1);
            frame.Size = new Size(_log.Width + 2, _log.Height + 2);
            frame.BackColor = Brand.Border;
            Controls.Add(frame);
            frame.SendToBack();
            _log.BringToFront();
            _status.BringToFront();
        }

        private Icon LoadAppIcon()
        {
            try
            {
                using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("tfast.ico"))
                    if (s != null) return new Icon(s, 32, 32);
            }
            catch { }
            return null;
        }

        // ------------------------------------------------------------------ actions
        private void ConfirmRestore()
        {
            DialogResult r = MessageBox.Show(
                "This undoes every change made by this program:\r\n\r\n" +
                "- settings.dat restored from backup\r\n" +
                "- compatibility flags removed\r\n" +
                "- GPU preference removed\r\n" +
                "- Game Bar, focus lock and notification settings restored\r\n" +
                "- Windows-start watchdog removed\r\n\r\n" +
                "Continue?",
                "Restore all changes",
                MessageBoxButtons.YesNo, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2);

            if (r == DialogResult.Yes)
                RunEngine(new string[] { "-Action", "Restore" }, "Restore all", false);
        }

        private void OpenGameFolder()
        {
            try
            {
                if (string.IsNullOrEmpty(_gameDir))
                {
                    MessageBox.Show("The game folder is unknown.", Brand.Agency,
                        MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return;
                }
                Process.Start("explorer.exe", "\"" + _gameDir + "\"");
            }
            catch (Exception ex) { Log("Could not open the folder: " + ex.Message); }
        }

        private void OpenUrl(string url)
        {
            try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); }
            catch (Exception ex) { Log("Could not open the link: " + ex.Message); }
        }

        private string ExtractScript()
        {
            string dir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "TFastDigital");
            Directory.CreateDirectory(dir);
            string target = Path.Combine(dir, ScriptResource);

            using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream(ScriptResource))
            {
                if (s == null)
                    throw new InvalidOperationException("The built-in fix engine is missing from this build.");
                using (FileStream fs = new FileStream(target, FileMode.Create, FileAccess.Write, FileShare.None))
                    s.CopyTo(fs);
            }
            return target;
        }

        private void RunEngine(string[] engineArgs, string title, bool quiet)
        {
            if (_running) return;

            string script;
            try { script = ExtractScript(); }
            catch (Exception ex)
            {
                Log("Error: " + ex.Message);
                Status("Cannot unpack the fix engine.", true);
                return;
            }

            StringBuilder a = new StringBuilder();
            a.Append("-NoProfile -ExecutionPolicy Bypass -File \"").Append(script).Append("\"");
            if (!string.IsNullOrEmpty(_gameDir)) a.Append(" -GameDir \"").Append(_gameDir).Append("\"");
            if (quiet) a.Append(" -Quiet");
            foreach (string s in engineArgs) a.Append(" \"").Append(s.Replace("\"", "\\\"")).Append("\"");

            Log("");
            Log("[" + title + "]");

            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe");
            if (!File.Exists(psi.FileName)) psi.FileName = "powershell.exe";
            psi.Arguments = a.ToString();
            psi.UseShellExecute = false;
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            psi.CreateNoWindow = true;
            psi.WorkingDirectory = string.IsNullOrEmpty(_gameDir) ? Path.GetDirectoryName(script) : _gameDir;
            try { psi.StandardOutputEncoding = Encoding.UTF8; } catch { }
            try { psi.StandardErrorEncoding = Encoding.UTF8; } catch { }

            try
            {
                _current = new Process();
                _current.StartInfo = psi;
                _current.EnableRaisingEvents = true;
                _current.OutputDataReceived += delegate (object s, DataReceivedEventArgs ev)
                {
                    if (ev.Data != null) LogLine(ev.Data);
                };
                _current.ErrorDataReceived += delegate (object s, DataReceivedEventArgs ev)
                {
                    if (!string.IsNullOrEmpty(ev.Data)) LogLine(ev.Data);
                };
                _current.Exited += delegate (object s, EventArgs ev)
                {
                    int code = 0;
                    try { code = _current.ExitCode; } catch { }
                    BeginInvoke(new Action<int>(delegate (int c) { EngineFinished(c); }), code);
                };

                SetBusy(true);
                Status("Working: " + title, false);
                _current.Start();
                _current.BeginOutputReadLine();
                _current.BeginErrorReadLine();
            }
            catch (Exception ex)
            {
                SetBusy(false);
                Log("Error: could not start the fix engine. " + ex.Message);
                Status("Failed to start.", true);
            }
        }

        private void StopEngine()
        {
            try
            {
                if (_current != null && !_current.HasExited)
                {
                    Log("Stopping.");
                    _current.Kill();
                }
            }
            catch (Exception ex) { Log(ex.Message); }
        }

        private void EngineFinished(int exitCode)
        {
            SetBusy(false);
            if (exitCode == 0)
            {
                Status("Done.", false);
                Log("");
                Log("Finished. Full log: %TEMP%\\PES2021Fullscreen.log");
            }
            else
            {
                Status("Finished with exit code " + exitCode + ".", true);
                Log("");
                Log("Finished with exit code " + exitCode + ".");
            }
        }

        private void SetBusy(bool busy)
        {
            _running = busy;
            SetActionsEnabled(!busy);
            _stop.Enabled = busy;
            _progress.Visible = busy;
            _progress.MarqueeAnimationSpeed = busy ? 25 : 0;
            UseWaitCursor = busy;
            _play.Text = busy ? "Working..." : "Play PES 2021";
        }

        private void SetActionsEnabled(bool on)
        {
            _play.Enabled = on;
            _install.Enabled = on;
            _gpu.Enabled = on;
            _diagnose.Enabled = on;
            _overlays.Enabled = on;
            _restore.Enabled = on;
            _folder.Enabled = on;
        }

        // ------------------------------------------------------------------ output
        private void Log(string text) { LogLine(text); }

        private void LogLine(string line)
        {
            if (_log == null) return;
            if (_log.InvokeRequired)
            {
                try { _log.BeginInvoke(new Action<string>(AppendLine), line); } catch { }
                return;
            }
            AppendLine(line);
        }

        private void AppendLine(string line)
        {
            if (_log.TextLength > 80000) _log.Clear();

            Color c = Brand.Text;
            if (line.IndexOf("[ok]", StringComparison.OrdinalIgnoreCase) >= 0) c = Brand.Ok;
            else if (line.IndexOf("[fail]", StringComparison.OrdinalIgnoreCase) >= 0) c = Brand.Fail;
            else if (line.IndexOf("[note]", StringComparison.OrdinalIgnoreCase) >= 0) c = Brand.Warn;
            else if (line.StartsWith("[") && line.EndsWith("]")) c = Brand.AccentHi;
            else if (line.StartsWith("Finished")) c = Brand.Muted;

            _log.SelectionStart = _log.TextLength;
            _log.SelectionLength = 0;
            _log.SelectionColor = c;
            _log.AppendText(line + Environment.NewLine);
            _log.SelectionColor = Brand.Text;
            _log.ScrollToCaret();
        }

        private void Status(string text, bool error)
        {
            if (_status == null) return;
            if (_status.InvokeRequired)
            {
                try { _status.BeginInvoke(new Action<string, bool>(Status), text, error); } catch { }
                return;
            }
            _status.Text = text;
            _status.ForeColor = error ? Brand.Warn : Brand.Muted;
        }

        // ------------------------------------------------------------------ entry
        [DllImport("user32.dll")]
        private static extern bool SetProcessDPIAware();

        [STAThread]
        private static void Main(string[] args)
        {
            try { SetProcessDPIAware(); } catch { }
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            string gameDir = null;
            for (int i = 0; i < args.Length; i++)
            {
                string bare = args[i].TrimStart('-', '/');
                if (string.Equals(bare, "GameDir", StringComparison.OrdinalIgnoreCase) &&
                    i + 1 < args.Length && Directory.Exists(args[i + 1]))
                {
                    gameDir = Path.GetFullPath(args[i + 1]);
                }
            }

            if (gameDir == null)
            {
                string[] candidates = new string[]
                {
                    AppDomain.CurrentDomain.BaseDirectory,
                    Directory.GetCurrentDirectory()
                };
                foreach (string d in candidates)
                {
                    if (!string.IsNullOrEmpty(d) && File.Exists(Path.Combine(d, "PES2021.exe")))
                    {
                        gameDir = d.TrimEnd(Path.DirectorySeparatorChar);
                        break;
                    }
                }
            }

            string[] passThrough = null;
            bool noUpdateCheck = false;
            if (args.Length > 0)
            {
                bool menu = false;
                List<string> keep = new List<string>();
                for (int i = 0; i < args.Length; i++)
                {
                    string bare = args[i].TrimStart('-', '/').ToLowerInvariant();
                    if (bare == "menu" || bare == "interactive") { menu = true; continue; }
                    if (bare == "noupdatecheck") { noUpdateCheck = true; continue; }
                    if (bare == "gamedir") { i++; continue; }
                    keep.Add(args[i]);
                }

                // Only pass switches through. A stray value usually means the caller forgot to
                // quote a path, and forwarding it would surface as a confusing option error.
                List<string> switches = new List<string>();
                foreach (string a in keep)
                {
                    string t = a.Trim();
                    if (t.Length > 0 && (t[0] == '-' || t[0] == '/')) switches.Add(t);
                }
                if (!menu && switches.Count > 0) passThrough = switches.ToArray();
            }

            using (MainForm f = new MainForm(gameDir, noUpdateCheck))
            {
                if (passThrough != null)
                {
                    string[] run = passThrough;
                    f.Shown += delegate { f.RunRawAction(run, "Command line"); };
                }
                Application.Run(f);
            }
        }

        private void RunRawAction(string[] engineArgs, string title)
        {
            RunEngine(engineArgs, title, false);
        }
    }
}
