<#
.SYNOPSIS
    Pharmacy Document Automation Pipeline
    
.DESCRIPTION
    Monitors a directory for incoming PDF documents. Uses Poppler Utils to parse text
    and classify documents (Invoice, Recipe, Protocol).
    - Invoices: Printed and filed.
    - Recipes: Routed to patient folders via fuzzy matching.
    - Protocols: Split into single pages and digitally signed (JSignPDF).

.NOTES
    Author: [Dein Name/Portfolio]
    Version: 1.0 (Anonymized for GitHub)
    Requirements: Java Runtime, Poppler Utils (pdftotext, pdfinfo, pdfseparate), JSignPDF
#>

# ---------------------------------------------------------------------------
# CONFIGURATION
# ---------------------------------------------------------------------------
$Config = @{
    # Paths
    InputPath      = "C:\AutoPipeline\Input"
    ProcessedPath  = "C:\AutoPipeline\Archive"
    ErrorPath      = "C:\AutoPipeline\Error"
    OrdersRoot     = "C:\PharmacyData\Orders"
    
    # Tools
    PopplerBin     = "C:\Tools\poppler\bin"
    JSignPdfJar    = "C:\Tools\JSignPDF\JSignPdf.jar"
    JavaPath       = "C:\Program Files\Java\jre1.8.0_361\bin\java.exe"
    
    # Signing Identity (PKCS12)
    KeystorePath   = "C:\Secrets\pharmacy_cert.p12"
    KeystorePass   = "MySecretPassword123!" # Use SecureString in production
    
    # Printer
    PrinterName    = "Brother HL-L6400DW Series"
    
    # Regex Patterns (German Keywords)
    RegexInvoice   = "Rechnung\s+Nr\.?|Faktura"
    RegexRecipe    = "Betäubungsmittelrezept|Kassenrezept"
    RegexProtocol  = "Herstellungsprotokoll|Freigabeprotokoll"
}

# Ensure directories exist
$Config.InputPath, $Config.ProcessedPath, $Config.ErrorPath | ForEach-Object {
    if (!(Test-Path $_)) { New-Item -ItemType Directory -Path $_ -Force | Out-Null }
}

# ---------------------------------------------------------------------------
# HELPER FUNCTIONS
# ---------------------------------------------------------------------------

function Write-Log {
    param([string]$Message, [string]$Level="INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$Timestamp] [$Level] $Message" -ForegroundColor ($Level -eq "ERROR" ? "Red" : "Cyan")
}

function Get-PdfText {
    param([string]$FilePath)
    
    $PdfToText = Join-Path $Config.PopplerBin "pdftotext.exe"
    $TempTxt = "$FilePath.txt"
    
    # Execute pdftotext (layout preservation helps with regex)
    $Proc = Start-Process -FilePath $PdfToText -ArgumentList "-layout `"$FilePath`" `"$TempTxt`"" -Wait -PassThru -NoNewWindow
    
    if (Test-Path $TempTxt) {
        $Content = Get-Content $TempTxt -Raw
        Remove-Item $TempTxt -Force
        return $Content
    }
    return $null
}

function Invoke-DigitalSigning {
    param([string]$FilePath)
    
    Write-Log "Initiating Signing Routine for: $(Split-Path $FilePath -Leaf)"
    
    $PdfInfo     = Join-Path $Config.PopplerBin "pdfinfo.exe"
    $PdfSeparate = Join-Path $Config.PopplerBin "pdfseparate.exe"
    
    # 1. Get Page Count
    $InfoOutput = & $PdfInfo "$FilePath"
    $Pages = ($InfoOutput | Select-String "Pages:\s+(\d+)").Matches.Groups[1].Value
    
    if (-not $Pages) { throw "Could not determine page count." }
    
    Write-Log "Document has $Pages pages. Splitting..."
    
    # 2. Split PDF into single pages (pattern: doc-1.pdf, doc-2.pdf...)
    $BaseName = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
    $SplitPattern = Join-Path $Config.ProcessedPath "${BaseName}-%d.pdf"
    
    Start-Process -FilePath $PdfSeparate -ArgumentList "`"$FilePath`" `"$SplitPattern`"" -Wait -NoNewWindow
    
    # 3. Loop and Sign each page
    for ($i = 1; $i -le [int]$Pages; $i++) {
        $SinglePage = Join-Path $Config.ProcessedPath "${BaseName}-$i.pdf"
        
        if (Test-Path $SinglePage) {
            Write-Log "Signing Page $i..."
            
            # Arguments for JSignPDF (Visual signature bottom right)
            $JArgs = @(
                "-jar", "`"$($Config.JSignPdfJar)`"",
                "$SinglePage",
                "-kst", "PKCS12",
                "-ksf", "`"$($Config.KeystorePath)`"",
                "-ksp", "`"$($Config.KeystorePass)`"",
                "-llx", "400", "-lly", "20",
                "-urx", "580", "-ury", "80", # Coordinates for visual sig
                "-V" # Visible signature
            )
            
            $SignProc = Start-Process -FilePath $Config.JavaPath -ArgumentList $JArgs -Wait -PassThru -NoNewWindow
            
            if ($SignProc.ExitCode -eq 0) {
                # Cleanup unsigned single page
                Remove-Item $SinglePage -Force
            } else {
                Write-Log "Failed to sign page $i" "ERROR"
            }
        }
    }
    Write-Log "Signing sequence complete."
}

# ---------------------------------------------------------------------------
# CORE LOGIC
# ---------------------------------------------------------------------------

function Process-File {
    param([System.IO.FileInfo]$File)
    
    try {
        Write-Log "Processing: $($File.Name)"
        
        # Wait for file lock release (simple retry logic)
        Start-Sleep -Seconds 1
        
        # 1. Parse Text
        $TextContent = Get-PdfText -FilePath $File.FullName
        
        if ([string]::IsNullOrWhiteSpace($TextContent)) {
            throw "Text extraction failed or empty."
        }
        
        # 2. Classification & Routing
        if ($TextContent -match $Config.RegexInvoice) {
            Write-Log "Type detected: INVOICE"
            
            # Action: Print
            Start-Process -FilePath $File.FullName -Verb PrintTo -ArgumentList $Config.PrinterName -Wait
            
            # Action: Move to Archive
            Move-Item -Path $File.FullName -Destination $Config.ProcessedPath -Force
            
        } 
        elseif ($TextContent -match $Config.RegexRecipe) {
            Write-Log "Type detected: RECIPE"
            
            # Action: Fuzzy Match Patient Name (Simplified for Demo)
            # In production, this parses "Name: Mustermann" and searches directories
            if ($TextContent -match "Name:\s+([a-zA-ZäöüÄÖÜ]+)") {
                $PatientName = $matches[1]
                $TargetDir = Get-ChildItem $Config.OrdersRoot -Directory | Where-Object { $_.Name -match $PatientName } | Select-Object -First 1
                
                if ($TargetDir) {
                    Move-Item -Path $File.FullName -Destination $TargetDir.FullName -Force
                    Write-Log "Moved to patient folder: $($TargetDir.Name)"
                } else {
                    Write-Log "Patient folder not found. Moving to manual review." "WARN"
                    Move-Item -Path $File.FullName -Destination $Config.ErrorPath -Force
                }
            }
            
        } 
        elseif ($TextContent -match $Config.RegexProtocol) {
            Write-Log "Type detected: PROTOCOL (Signing required)"
            
            # Action: Split & Sign
            Invoke-DigitalSigning -FilePath $File.FullName
            
            # Remove original input file after successful processing
            Remove-Item -Path $File.FullName -Force
            
        } 
        else {
            Write-Log "Unknown Document Type. Moving to Error." "WARN"
            Move-Item -Path $File.FullName -Destination $Config.ErrorPath -Force
        }
        
    } catch {
        Write-Log "Error processing $($File.Name): $_" "ERROR"
        Move-Item -Path $File.FullName -Destination $Config.ErrorPath -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# MAIN LOOP (WATCHER)
# ---------------------------------------------------------------------------

Write-Log "Service Started. Watching $($Config.InputPath)..."

while ($true) {
    $Files = Get-ChildItem -Path $Config.InputPath -Filter "*.pdf"
    
    foreach ($File in $Files) {
        Process-File -File $File
    }
    
    Start-Sleep -Seconds 5
}
