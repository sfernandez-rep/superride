<#
.SYNOPSIS
   Generates the SuperR icon set and installer artwork from the logo master.
   SPDX-License-Identifier: AGPL-3.0-only

.DESCRIPTION
   Reads assets\branding\source\logo-master.png (never modified) and writes
   assets\branding\generated\:

     png\superr-<size>.png   transparent square icons, 16 to 1024 px
     superr.ico              multi-resolution Windows icon (16-256 px;
                             32-bit DIB entries up to 128 px, PNG at 256)
     installer-header.bmp    NSIS Modern UI header image (150 x 57)
     installer-welcome.bmp   NSIS Modern UI welcome/finish image (164 x 314)
     contact-sheet.png       every size on light, dark and checkerboard
                             backgrounds, at 1x and magnified, for review
     manifest.txt            source hash, cleanup counts, output hashes

   and copies png\superr-96.png to the GWT client sources (About dialog logo,
   src\gwt\...\views\superrstudio\superr-logo-96.png).

   Cleanup applied in memory, in this order:
     1. alpha below 16 becomes 0: removes the faint haze spread over the
        master canvas (invisible at full size, it would enlarge the crop)
     2. alpha 248 and above becomes 255: the master body is alpha 253, which
        would leave every icon very slightly see-through
     3. the image is cropped to the remaining content and centred on a
        square canvas; proportions are never changed
   Edge antialiasing (alpha 16-247) is kept as drawn.

   Uses only Windows PowerShell 5.1 and System.Drawing (GDI+); the output
   is deterministic for a given master and Windows GDI+ version.

.EXAMPLE
   tools\superrstudio\branding\make-branding.ps1
#>
[CmdletBinding()]
param(
   [string]$Source = (Join-Path $PSScriptRoot '..\..\..\assets\branding\source\logo-master.png'),
   [string]$OutDir = (Join-Path $PSScriptRoot '..\..\..\assets\branding\generated')
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.IO;
using System.Runtime.InteropServices;

public static class SuperRBranding
{
   public static int HazeRemoved, BodyMadeOpaque;

   static byte[] Pixels(Bitmap bmp, out int stride)
   {
      var rect = new Rectangle(0, 0, bmp.Width, bmp.Height);
      var data = bmp.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
      stride = data.Stride;
      var bytes = new byte[stride * bmp.Height];
      Marshal.Copy(data.Scan0, bytes, 0, bytes.Length);
      bmp.UnlockBits(data);
      return bytes;
   }

   static Bitmap FromPixels(byte[] bytes, int w, int h, int stride)
   {
      var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
      var data = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
      for (int y = 0; y < h; y++)
         Marshal.Copy(bytes, y * stride, data.Scan0 + y * data.Stride, w * 4);
      bmp.UnlockBits(data);
      return bmp;
   }

   // cleaned, cropped and squared master (content touches the square on its long side)
   public static Bitmap Prepare(string path)
   {
      using (var src = new Bitmap(path))
      {
         int w = src.Width, h = src.Height, stride;
         var px = Pixels(src, out stride);
         int minX = w, minY = h, maxX = -1, maxY = -1;
         HazeRemoved = 0; BodyMadeOpaque = 0;
         for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
            {
               int i = y * stride + 4 * x;
               byte a = px[i + 3];
               if (a > 0 && a < 16) { px[i] = px[i + 1] = px[i + 2] = px[i + 3] = 0; HazeRemoved++; continue; }
               if (a >= 248 && a < 255) { px[i + 3] = 255; BodyMadeOpaque++; }
               if (px[i + 3] > 0)
               {
                  if (x < minX) minX = x; if (x > maxX) maxX = x;
                  if (y < minY) minY = y; if (y > maxY) maxY = y;
               }
            }
         if (maxX < 0) throw new Exception("The master has no visible content.");
         int cw = maxX - minX + 1, ch = maxY - minY + 1, side = Math.Max(cw, ch);
         var square = new byte[side * side * 4];
         int ox = (side - cw) / 2, oy = (side - ch) / 2;
         for (int y = 0; y < ch; y++)
            Buffer.BlockCopy(px, (minY + y) * stride + 4 * minX, square, ((oy + y) * side + ox) * 4, cw * 4);
         return FromPixels(square, side, side, side * 4);
      }
   }

   static Bitmap ResizeOnce(Bitmap src, int w, int h)
   {
      // premultiplied alpha: transparent pixels carry no colour into the
      // edge, so downscaling leaves no dark halo
      var dst = new Bitmap(w, h, PixelFormat.Format32bppPArgb);
      using (var g = Graphics.FromImage(dst))
      using (var attrs = new ImageAttributes())
      {
         attrs.SetWrapMode(WrapMode.TileFlipXY);
         g.CompositingMode = CompositingMode.SourceCopy;
         g.CompositingQuality = CompositingQuality.HighQuality;
         g.InterpolationMode = InterpolationMode.HighQualityBicubic;
         g.PixelOffsetMode = PixelOffsetMode.HighQuality;
         g.SmoothingMode = SmoothingMode.HighQuality;
         g.DrawImage(src, new Rectangle(0, 0, w, h), 0, 0, src.Width, src.Height, GraphicsUnit.Pixel, attrs);
      }
      return dst;
   }

   // progressive halving, then one bicubic step to the exact size
   static Bitmap Resize(Bitmap src, int size)
   {
      Bitmap cur = src;
      while (cur.Width / 2 >= size * 2)
      {
         var next = ResizeOnce(cur, cur.Width / 2, cur.Height / 2);
         if (cur != src) cur.Dispose();
         cur = next;
      }
      var result = ResizeOnce(cur, size, size);
      if (cur != src) cur.Dispose();
      return result;
   }

   // icon of the given size; small sizes use less padding to stay legible
   public static Bitmap Icon(Bitmap master, int size)
   {
      double margin = size <= 32 ? 0.03 : 0.06;
      int inner = Math.Max(1, (int)Math.Round(size * (1 - 2 * margin)));
      var canvas = new Bitmap(size, size, PixelFormat.Format32bppArgb);
      using (var glyph = Resize(master, inner))
      using (var g = Graphics.FromImage(canvas))
      {
         g.Clear(Color.Transparent);
         g.CompositingMode = CompositingMode.SourceCopy;
         int off = (size - inner) / 2;
         g.DrawImageUnscaled(glyph, off, off);
      }
      return canvas;
   }

   public static void SavePng(Bitmap bmp, string path)
   {
      using (var copy = new Bitmap(bmp.Width, bmp.Height, PixelFormat.Format32bppArgb))
      {
         using (var g = Graphics.FromImage(copy)) { g.CompositingMode = CompositingMode.SourceCopy; g.DrawImageUnscaled(bmp, 0, 0); }
         copy.Save(path, ImageFormat.Png);
      }
   }

   static byte[] PngBytes(Bitmap bmp)
   {
      using (var ms = new MemoryStream()) { bmp.Save(ms, ImageFormat.Png); return ms.ToArray(); }
   }

   // classic 32-bit DIB icon entry (BGRA bottom-up + 1-bit AND mask)
   static byte[] DibBytes(Bitmap bmp)
   {
      int w = bmp.Width, h = bmp.Height, stride;
      var px = Pixels(bmp, out stride);
      int maskStride = ((w + 31) / 32) * 4;
      using (var ms = new MemoryStream())
      using (var bw = new BinaryWriter(ms))
      {
         bw.Write(40); bw.Write(w); bw.Write(h * 2); bw.Write((short)1); bw.Write((short)32);
         bw.Write(0); bw.Write(w * h * 4 + maskStride * h); bw.Write(0); bw.Write(0); bw.Write(0); bw.Write(0);
         for (int y = h - 1; y >= 0; y--) bw.Write(px, y * stride, w * 4);
         for (int y = h - 1; y >= 0; y--)
         {
            var row = new byte[maskStride];
            for (int x = 0; x < w; x++)
               if (px[y * stride + 4 * x + 3] == 0) row[x / 8] |= (byte)(0x80 >> (x % 8));
            bw.Write(row);
         }
         return ms.ToArray();
      }
   }

   public static void SaveIco(Bitmap[] icons, string path)
   {
      var images = new List<byte[]>();
      foreach (var b in icons) images.Add(b.Width >= 256 ? PngBytes(b) : DibBytes(b));
      using (var fs = new FileStream(path, FileMode.Create))
      using (var bw = new BinaryWriter(fs))
      {
         bw.Write((short)0); bw.Write((short)1); bw.Write((short)icons.Length);
         int offset = 6 + 16 * icons.Length;
         for (int i = 0; i < icons.Length; i++)
         {
            int s = icons[i].Width;
            bw.Write((byte)(s >= 256 ? 0 : s)); bw.Write((byte)(s >= 256 ? 0 : s));
            bw.Write((byte)0); bw.Write((byte)0); bw.Write((short)1); bw.Write((short)32);
            bw.Write(images[i].Length); bw.Write(offset);
            offset += images[i].Length;
         }
         foreach (var img in images) bw.Write(img);
      }
   }

   static void Text(Graphics g, string s, string family, float px, FontStyle style, Color c, RectangleF r, StringAlignment align)
   {
      using (var f = new Font(family, px, style, GraphicsUnit.Pixel))
      using (var b = new SolidBrush(c))
      using (var fmt = new StringFormat { Alignment = align, LineAlignment = StringAlignment.Center })
         g.DrawString(s, f, b, r, fmt);
   }

   static Graphics Quality(Bitmap bmp)
   {
      var g = Graphics.FromImage(bmp);
      g.InterpolationMode = InterpolationMode.HighQualityBicubic;
      g.SmoothingMode = SmoothingMode.HighQuality;
      g.PixelOffsetMode = PixelOffsetMode.HighQuality;
      g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
      return g;
   }

   // NSIS bitmaps are 24-bit: the logo is composited on white
   public static void InstallerHeader(Bitmap master, string path)
   {
      using (var bmp = new Bitmap(150, 57, PixelFormat.Format24bppRgb))
      {
         using (var g = Quality(bmp))
         using (var logo = Icon(master, 48))
         {
            g.Clear(Color.White);
            g.DrawImage(logo, 98, 4, 48, 48);
         }
         bmp.Save(path, ImageFormat.Bmp);
      }
   }

   public static void InstallerWelcome(Bitmap master, string path, string name, string tagline)
   {
      using (var bmp = new Bitmap(164, 314, PixelFormat.Format24bppRgb))
      {
         using (var g = Quality(bmp))
         using (var logo = Icon(master, 120))
         using (var band = new LinearGradientBrush(new Rectangle(0, 0, 164, 314), Color.FromArgb(240, 246, 255), Color.White, 90f))
         {
            g.FillRectangle(band, 0, 0, 164, 314);
            g.DrawImage(logo, 22, 56, 120, 120);
            Text(g, name, "Segoe UI Semibold", 26f, FontStyle.Regular, Color.FromArgb(16, 42, 92), new RectangleF(0, 186, 164, 40), StringAlignment.Center);
            Text(g, tagline, "Segoe UI", 12f, FontStyle.Regular, Color.FromArgb(70, 84, 110), new RectangleF(0, 224, 164, 22), StringAlignment.Center);
         }
         bmp.Save(path, ImageFormat.Bmp);
      }
   }

   public static void ContactSheet(Bitmap[] icons, string path)
   {
      Color[] backs = { Color.White, Color.FromArgb(30, 30, 30), Color.Empty };
      int pad = 12, rowH = 0, width = pad;
      foreach (var b in icons) { width += Math.Max(b.Width, 64) + pad; }
      foreach (var b in icons) rowH = Math.Max(rowH, b.Width);
      int zoom = 4, zoomRow = 32 * zoom, height = 3 * (rowH + 2 * pad) + 3 * (zoomRow + 2 * pad);
      using (var sheet = new Bitmap(width, height, PixelFormat.Format32bppArgb))
      using (var g = Graphics.FromImage(sheet))
      {
         g.Clear(Color.White);
         int y = 0;
         for (int pass = 0; pass < 2; pass++)
         {
            int h = pass == 0 ? rowH : zoomRow;
            for (int r = 0; r < 3; r++)
            {
               var area = new Rectangle(0, y, width, h + 2 * pad);
               if (backs[r] == Color.Empty)
               {
                  for (int cy = area.Top; cy < area.Bottom; cy += 8)
                     for (int cx = 0; cx < width; cx += 8)
                        using (var b = new SolidBrush(((cx / 8 + cy / 8) % 2 == 0) ? Color.FromArgb(204, 204, 204) : Color.White))
                           g.FillRectangle(b, cx, cy, 8, 8);
               }
               else using (var b = new SolidBrush(backs[r])) g.FillRectangle(b, area);
               int x = pad;
               foreach (var icon in icons)
               {
                  if (pass == 0) g.DrawImageUnscaled(icon, x, y + pad);
                  else if (icon.Width <= 32)
                  {
                     g.InterpolationMode = InterpolationMode.NearestNeighbor;
                     g.PixelOffsetMode = PixelOffsetMode.Half;
                     g.DrawImage(icon, x, y + pad, icon.Width * zoom, icon.Height * zoom);
                  }
                  x += Math.Max(icon.Width, pass == 0 ? 64 : icon.Width <= 32 ? icon.Width * zoom : 0) + (pass == 1 && icon.Width > 32 ? 0 : pad);
               }
               y += h + 2 * pad;
            }
         }
         sheet.Save(path, ImageFormat.Png);
      }
   }
}
'@

$Source = (Resolve-Path $Source).Path
New-Item -ItemType Directory -Force (Join-Path $OutDir 'png') | Out-Null
$OutDir = (Resolve-Path $OutDir).Path
$sourceHash = (Get-FileHash $Source -Algorithm SHA256).Hash

$master = [SuperRBranding]::Prepare($Source)
$sizes = 16, 20, 24, 32, 40, 48, 64, 96, 128, 256, 512, 1024
$icons = @{}
foreach ($s in $sizes)
{
   $icons[$s] = [SuperRBranding]::Icon($master, $s)
   [SuperRBranding]::SavePng($icons[$s], (Join-Path $OutDir "png\superr-$s.png"))
}
$icoSizes = 16, 20, 24, 32, 40, 48, 64, 96, 128, 256
[SuperRBranding]::SaveIco([System.Drawing.Bitmap[]]($icoSizes | ForEach-Object { $icons[$_] }), (Join-Path $OutDir 'superr.ico'))
[SuperRBranding]::InstallerHeader($master, (Join-Path $OutDir 'installer-header.bmp'))
[SuperRBranding]::InstallerWelcome($master, (Join-Path $OutDir 'installer-welcome.bmp'), 'SuperR', 'Preview')
[SuperRBranding]::ContactSheet([System.Drawing.Bitmap[]](16, 24, 32, 48, 64, 128, 256 | ForEach-Object { $icons[$_] }), (Join-Path $OutDir 'contact-sheet.png'))

$lines = @(
   'SuperR branding assets, generated by tools/superrstudio/branding/make-branding.ps1',
   "source: assets/branding/source/$(Split-Path $Source -Leaf)",
   "source sha256: $sourceHash",
   "master content square: $($master.Width) px",
   "haze pixels removed (alpha < 16): $([SuperRBranding]::HazeRemoved)",
   "body pixels made opaque (alpha 248-254): $([SuperRBranding]::BodyMadeOpaque)",
   '')
foreach ($file in Get-ChildItem $OutDir -Recurse -File | Where-Object Name -ne 'manifest.txt' | Sort-Object FullName)
{
   $rel = $file.FullName.Substring($OutDir.Length + 1).Replace('\', '/')
   $lines += "{0}  {1}" -f (Get-FileHash $file.FullName -Algorithm SHA256).Hash.ToLower(), $rel
}
Set-Content -Path (Join-Path $OutDir 'manifest.txt') -Value $lines -Encoding ascii
Copy-Item (Join-Path $OutDir 'png\superr-96.png') (Join-Path $PSScriptRoot '..\..\..\src\gwt\src\org\rstudio\studio\client\workbench\views\superrstudio\superr-logo-96.png')
foreach ($b in $icons.Values) { $b.Dispose() }
$master.Dispose()
Write-Host "Branding assets written to $OutDir"
