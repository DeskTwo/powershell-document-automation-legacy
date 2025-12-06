# Pharmacy Document Automation Pipeline

> **Automated document pipeline for pharmacy compliance. Monitors input streams, parses text (Poppler) to categorize and route invoices/recipes. Features an integrated workflow for splitting and digitally signing multi-page protocols (JSignPDF).**

## 📋 Overview

This PowerShell-based solution operates as a background service to automate the influx of digital documents in a high-volume pharmacy environment. It eliminates the need for manual sorting, printing, and signing of sensitive medical documents.

By integrating robust command-line tools (Poppler Utils, Java-based JSignPDF), the script bridges the gap between receiving a generic PDF and filing a legally compliant, signed, and sorted document.

## ⚡ The Challenge

The client faced a bottleneck involving thousands of incoming PDF documents monthly:
*   **Invoices** needed immediate printing and specific folder filing.
*   **Medical Recipes** required fuzzy matching to associate them with existing patient orders based on name parsing.
*   **Release Protocols** required a qualified digital signature (visual & cryptographic) on *every single page* to meet regulatory standards.

Manual processing resulted in high administrative costs and human filing errors.

## 🚀 Key Features

*   **Real-time Monitoring:** Uses `.NET FileSystemWatcher` to detect incoming files instantly.
*   **Content-Aware Routing:** Extracts text layers using `pdftotext` to classify documents via Regex (Invoice vs. Recipe vs. Protocol).
*   **Intelligent Fuzzy Matching:** Matches incoming recipes to patient folders even with slight naming variations.
*   **Granular Digital Signing:**
    *   Solves the complexity of signing multi-page PDFs without breaking cryptographic validity.
    *   Splits multi-page protocols into individual components.
    *   Applies a visual signature (Bottom-Right) and cryptographic seal to each page using `JSignPDF`.
*   **Auto-Print Dispatch:** Sends specific document types to the hardware printer automatically.

## 🛠️ Tech Stack

*   **Core:** PowerShell 5.1 / 7 (Scripting & Logic)
*   **PDF Parsing:** Poppler Utils (`pdftotext`, `pdfinfo`, `pdfseparate`)
*   **Digital Signatures:** JSignPDF (Java-based CLI tool), PKCS#12 Keystore
*   **Environment:** Windows Server / Desktop

## ⚙️ Workflow Logic

1.  **Ingest:** Script watches the defined `DownloadDir`.
2.  **Parse:** Incoming PDF is converted to raw text for analysis.
3.  **Classify:**
    *   *If Invoice:* Create directory based on `Name + Date`, print, and move.
    *   *If Recipe:* Search existing directories for Name match (fuzzy logic), move to patient folder.
    *   *If Protocol:* Initiate Signing Routine.
4.  **Signing Routine:**
    *   Detect page count via `pdfinfo`.
    *   Split PDF into single pages via `pdfseparate`.
    *   Loop through pages and apply `LocalAdES` signature via Java call.
    *   Store signed pages in the target directory.

## 🔧 Configuration

The script is controlled via a central configuration block. Adjust paths before deployment:

```powershell
$global:CFG = [ordered]@{
    DownloadDir    = 'C:\Users\...\Downloads'
    OrdersRoot     = 'C:\...\Orders'
    PrinterName    = 'Office Printer'
    PdfToolsDir    = 'C:\Tools\poppler\bin'
    JSignPdfPath   = 'C:\Tools\JSignPDF\JSignPdf.jar'
    # ...
    SigRect        = @{ llx = 400; lly = 20; urx = 600; ury = 100 } # Bottom Right
}

Usage

Run the script in a PowerShell session with administrative privileges (required for file system events and printer access).
powershell -ExecutionPolicy Bypass -File ".\document_processor.ps1"
