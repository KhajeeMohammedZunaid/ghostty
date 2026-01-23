# AUTO-DELETION LOGIC (BYPASS PROTOCOL)

## 1. The "Why" (Root Cause)
The app is currently using standard `MediaStore` or `PhotoManager` methods, which respect OS "Scoped Storage" rules. These rules force a system popup for every deletion event to protect user data.

## 2. The Solution (Platform Specifics)

### A. Android (The "Root" Approach)
Since this is a personal app, we will request **All Files Access** (`MANAGE_EXTERNAL_STORAGE`).
* **Effect:** This grants the app "Root-like" access to the file system.
* **Result:** We can use standard Dart `File(path).delete()` commands instead of `PhotoManager` commands. Standard file commands **DO NOT** trigger the "Allow deletion?" popup.



---

## 3. The Implementation Script (Flutter)

**Step 1: Update `AndroidManifest.xml`**
Add this specific permission. It is dangerous for Play Store apps, but perfect for personal use.
```xml
<manifest ...>
    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE" />
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
</manifest>