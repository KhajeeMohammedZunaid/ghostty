# GHOST JOURNAL: CANVAS PROTOCOL
**Version:** 3.0 (Canvas Edition)
**Objective:** Implement "Cinematic" notes where user-selected images serve as encrypted backgrounds.
**Design System:** ThreadDev Aesthetic (Immersive, Dark, Motion-Rich).

---

## 1. Core Architecture (Security Foundation)
* **Database:** `sqflite_sqlcipher` (AES-256).
* **Key Storage:** `flutter_secure_storage` (Hardware-backed).
* **Auth:** `local_auth` (Biometrics required on entry/resume).
* **Offline:** Zero cloud sync.

---

## 2. The Canvas Feature (Logic & Data)

### 2.1 Database Schema Update
Modify the `JournalEntry` model to support background references.
* **Field:** `background_id` (String, UUID) - Links to the encrypted file.
* **Field:** `overlay_opacity` (Double) - User preference (0.0 to 1.0) to darken the image for readability.

### 2.2 "Set Background" Workflow
1.  **Input:** User taps "Set Canvas" icon in Editor.
2.  **Selection:** Trigger `image_picker` to select from Gallery.
3.  **Processing:**
    * **Crop:** Use `image_cropper` to enforce 9:16 (vertical) aspect ratio.
    * **Encrypt:** Generate UUID -> Encrypt bytes (AES) -> Save to `ApplicationDocumentsDirectory/backgrounds/UUID.ghost`.
4.  **Save:** Update the SQLite entry with the new `background_id`.
5.  **Cleanup:** If a previous background existed for this note, **delete** the old encrypted file immediately to save space.

---

## 3. UI/UX: The "Cinematic" Editor

### 3.1 The Layer Stack
Implement the Editor screen using a `Stack` widget:
1.  **Layer 1 (Bottom):** `Image.file` (The Decrypted Background).
    * *Fit:* `BoxFit.cover` (Fills entire screen).
2.  **Layer 2 (The Shield):** `Container` (Black Color).
    * *Opacity:* Bound to the `overlay_opacity` value (Default: 0.5).
    * *Interaction:* If the user drags a slider, update this opacity in real-time.
3.  **Layer 3 (Top):** The `QuillEditor` (Text Input).
    * *Text Color:* Fixed to **White/Off-White** (High Contrast).
    * *Padding:* `Symmetric(horizontal: 20)` to prevent text touching edges.

### 3.2 The Main Feed (Gallery View)
* **Design:** Replace standard list with a **Masonry or Card Grid**.
* **Card Content:**
    * Background: The note's image (dimmed).
    * Overlay: Title, Date, and a 2-line preview of the text.
* **Empty State:** If no image is set, use a solid "ThreadDev Dark Grey" or a generated gradient.

---

## 4. Implementation Directives
* **Dependencies:** `image_picker`, `image_cropper`, `uuid`, `path_provider`.
* **Performance:** Decrypt images into memory (`Uint8List`) only when the screen opens. Do not decrypt all backgrounds on the main feed simultaneously (use lazy loading or cache).
* **Permissions:** `READ_MEDIA_IMAGES` (Android) / `NSPhotoLibraryUsageDescription` (iOS). No special "Delete" permissions needed (Read-only access).

---
*End of Protocol.*