param (
    [Parameter(Mandatory=$true)][string]$VideoPath,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [int]$Width = 320,
    [int]$Height = 180
)

$code = @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public class ShellThumbnailExtractor
{
    [ComImport]
    [Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IShellItemImageFactory
    {
        [PreserveSig]
        int GetImage(
            [In, MarshalAs(UnmanagedType.Struct)] SIZE size,
            [In] SIIGBF flags,
            [Out] out IntPtr phbm);
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct SIZE
    {
        public int cx;
        public int cy;
        public SIZE(int cx, int cy) { this.cx = cx; this.cy = cy; }
    }

    [Flags]
    public enum SIIGBF
    {
        SIIGBF_RESIZETOFIT = 0x00,
        SIIGBF_BIGGERSIZEOK = 0x01,
        SIIGBF_MEMORYONLY = 0x02,
        SIIGBF_ICONONLY = 0x04,
        SIIGBF_THUMBNAILONLY = 0x08,
        SIIGBF_INCACHEONLY = 0x10
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
    public static extern void SHCreateItemFromParsingName(
        [In, MarshalAs(UnmanagedType.LPWStr)] string pszPath,
        [In] IntPtr pbc,
        [In, MarshalAs(UnmanagedType.LPStruct)] Guid riid,
        [Out, MarshalAs(UnmanagedType.Interface)] out IShellItemImageFactory ppv);

    [DllImport("gdi32.dll")]
    public static extern bool DeleteObject(IntPtr hObject);

    public static bool ExtractThumbnail(string videoPath, string outputPath, int width, int height)
    {
        try
        {
            Guid guid = new Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b");
            IShellItemImageFactory factory;
            SHCreateItemFromParsingName(videoPath, IntPtr.Zero, guid, out factory);
            if (factory == null) return false;

            IntPtr hBitmap;
            int hr = factory.GetImage(new SIZE(width, height), SIIGBF.SIIGBF_BIGGERSIZEOK | SIIGBF.SIIGBF_RESIZETOFIT, out hBitmap);
            if (hr != 0 || hBitmap == IntPtr.Zero) return false;

            using (Bitmap bmp = Bitmap.FromHbitmap(hBitmap))
            {
                bmp.Save(outputPath, ImageFormat.Jpeg);
            }
            DeleteObject(hBitmap);
            return true;
        }
        catch
        {
            return false;
        }
    }
}
"@

Add-Type -TypeDefinition $code -ReferencedAssemblies System.Drawing -ErrorAction SilentlyContinue

$dir = Split-Path -Parent $OutputPath
if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}

$res = [ShellThumbnailExtractor]::ExtractThumbnail($VideoPath, $OutputPath, $Width, $Height)
if ($res -and (Test-Path $OutputPath)) {
    Write-Host "SUCCESS: $OutputPath"
    exit 0
} else {
    Write-Error "FAILED"
    exit 1
}
