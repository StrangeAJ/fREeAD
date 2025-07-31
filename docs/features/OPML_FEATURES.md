# OPML Import/Export Feature

## Overview
The FreeAd RSS reader now supports OPML (Outline Processor Markup Language) import and export functionality, making it easy to migrate your RSS feeds from other feed readers or share your feed subscriptions.

## Features

### Import OPML
- **Location**: Feed Management Screen → Import OPML button (upload icon)
- **Supported formats**: .opml and .xml files
- **Process**:
  1. Click the import button in the app bar
  2. Select your OPML file from the file picker
  3. Preview all feeds found in the file
  4. Select/deselect feeds you want to import
  5. Click "Import Selected" to add them to your feed list

### Export OPML
- **Location**: Feed Management Screen → Export OPML button (download icon)
- **Options**:
  - **Save File**: Save the OPML file to your device
  - **Share**: Share the OPML file via system share sheet
- **Content**: Exports all your active feeds organized by categories

## Category Mapping
When importing OPML files, the system automatically maps common category names to the predefined categories:

- `tech`, `technology`, `programming`, `development` → **Technology**
- `news`, `general`, `world` → **General**
- `sport`, `sports` → **Sports**
- `entertainment`, `movies`, `tv` → **Entertainment**
- `business`, `finance`, `money` → **Business**
- Unknown categories → **General** (default)

## OPML Format Support
The implementation supports the standard OPML 1.0 format with the following elements:
- `xmlUrl`: RSS feed URL (required)
- `title` or `text`: Feed title
- `description`: Feed description
- `category`: Category name for organization
- `htmlUrl`: Website URL (optional)

## Example OPML Structure
```xml
<?xml version="1.0" encoding="UTF-8"?>
<opml version="1.0">
  <head>
    <title>My RSS Feeds</title>
  </head>
  <body>
    <outline text="Technology" title="Technology">
      <outline type="rss" text="TechCrunch" title="TechCrunch" 
               xmlUrl="https://feeds.feedburner.com/TechCrunch" 
               htmlUrl="https://techcrunch.com" 
               description="Technology news" 
               category="Technology"/>
    </outline>
  </body>
</opml>
```

## Migration from Other Feed Readers
This OPML support makes it easy to migrate from popular feed readers like:
- Feedly
- Inoreader
- The Old Reader
- NewsBlur
- And many others

Simply export your feeds as OPML from your current reader and import them into FreeAd.

## Technical Implementation
- **Parser**: Uses XML parsing with proper error handling
- **File Operations**: Supports both local file system and sharing
- **Validation**: Validates OPML structure and feed URLs
- **Batch Import**: Efficiently imports multiple feeds with progress feedback
- **Category Organization**: Automatically organizes feeds by category
