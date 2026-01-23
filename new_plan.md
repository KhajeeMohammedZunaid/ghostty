GHOST JOURNAL: NOTIFICATION & ALARM PROTOCOL
1. Permission Architecture (The Gatekeeper)
Since Android 13, you cannot simply "send" notifications. You must navigate a specific permission hierarchy.

1.1 The "Post Notification" Gate (Android 13+ & iOS)
Trigger: When the user first attempts to enable a reminder or toggles the "Notifications" setting.

Logic:

Check the current status of the Notification Permission.

If Status is "Denied": You must display a custom dialog explaining why the user needs to enable it. If they agree, redirect them to the System App Settings screen (programmatically) because you cannot ask the OS again.

If Status is "Undetermined": Trigger the system permission popup.

If Status is "Granted": Proceed to scheduling.

1.2 The "Exact Alarm" Gate (Android 12+)
The Issue: By default, Android delays notifications by a few minutes to save battery. For a specific "Alarm" (e.g., exactly at 8:00 AM), you need a special privilege.

Logic:

Check if the "Schedule Exact Alarm" permission is granted.

If Denied: You must direct the user to the specific "Alarms & Reminders" settings page.

Constraint: This is a "Special App Access" permission, not a standard popup. You must guide the user there gently.

2. Infrastructure Setup (The Engine)
2.1 Notification Channels (Android Mandatory)
You must configure a "High Importance" channel during app initialization.

Channel ID: ghost_todo_channel

Channel Name: "Task Reminders"

Importance Level: Set to Max/High. This ensures the notification makes a sound and visually "pops up" on the screen (Heads-up Notification) rather than silently appearing in the tray.

Lock Screen Visibility: Set to "Public" or "Private" depending on whether you want the task text visible on a locked phone.

2.2 Timezone Management
Critical Requirement: You cannot schedule alarms using generic UTC time. You must fetch the device's Local Timezone (e.g., "America/New_York" or "Asia/Kolkata").

Logic:

On app launch, detect the device's local timezone.

When scheduling a task, convert the user's picked date/time into a "Zoned Date Time" object using that detected location. This handles Daylight Savings Time changes automatically.

3. The Scheduling Workflow (Creation)
3.1 Uniqueness Strategy
Every To-Do item in your database has a unique ID (likely a UUID or String).

The Problem: The system notification scheduler requires an Integer ID.

The Solution: You must create a consistent hashing algorithm that converts your To-Do UUID into a unique 32-bit Integer. Use this Integer ID to schedule the notification. This allows you to find and cancel it later.

3.2 The "Set Alarm" Logic
Input: User selects a Date and Time.

Validation: Ensure the selected time is in the future.

Scheduling: Invoke the platform's "Zoned Schedule" method.

Payload: Attach the To-Do ID as data inside the notification. If the user taps the notification, the app opens and uses this ID to navigate directly to the specific task.

Wake Lock: Enable "Allow While Idle." This forces the alarm to ring even if the phone is in "Doze Mode" (battery saving sleep).

4. Lifecycle Management (Updates & Deletion)
4.1 "Mark as Done" / Delete
Trigger: User checks the box or deletes the task.

Action: Immediately call the "Cancel Notification" method using the Integer ID derived from the task.

Result: The future alarm is removed from the system scheduler.

4.2 Editing Time
Trigger: User changes the due date.

Action:

Cancel the existing notification ID.

Schedule a new notification with the new time using the same ID.

5. The Reboot Problem (Crucial for Offline Apps)
The Flaw: When an Android device reboots, all scheduled notifications and alarms are wiped by the OS.

The Fix: You must implement a "Boot Receiver."

Permission: Add the "Receive Boot Completed" permission to the Android Manifest.

Logic:

When the phone turns on, the OS broadcasts a "Boot Completed" signal.

Your app intercepts this signal in the background (without opening the UI).

The app queries your local database for all "Active/Pending" tasks.

It silently re-schedules all the alarms for those tasks.

6. Summary of User Experience
Setup: User taps "Remind me at 9 PM."

Permission: App asks "Allow Notifications?" (Once).

Wait: User closes the app and puts the phone in their pocket.

Trigger: At 9:00 PM exact, the phone rings/vibrates.

Interaction: User taps the notification -> App opens directly to that specific To-Do note.

End of Protocol.