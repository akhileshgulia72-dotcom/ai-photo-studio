package com.agdevelops.ainotescanner

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.view.accessibility.AccessibilityEvent

class FocusAccessibilityService : AccessibilityService() {

    companion object {
        var blockedPackages: Set<String> = emptySet()
        var focusEnabled: Boolean = false
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (!focusEnabled) return

        val packageName = event?.packageName?.toString()
            ?: return

        if (blockedPackages.contains(packageName)) {
            val intent = Intent(this, MainActivity::class.java)

            intent.addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            )

            intent.putExtra("focus_blocked_app", packageName)

            startActivity(intent)
        }
    }

    override fun onInterrupt() {
        // Nothing to do.
    }
}