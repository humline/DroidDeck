package com.droiddeck.launcher.session

import android.content.Context
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
class ArtworkPrefsTest {
    private val context get() = RuntimeEnvironment.getApplication()

    @Before fun clearSettings() {
        context.getSharedPreferences("session", Context.MODE_PRIVATE).edit().clear().commit()
    }

    @Test fun artworkLookupsDefaultOffAndCanBeEnabledOrDisabled() {
        assertFalse(SessionPrefs.addedGamesArt(context))
        assertFalse(SessionPrefs.emulatorArtwork(context))

        SessionPrefs.setAddedGamesArt(context, true)
        SessionPrefs.setEmulatorArtwork(context, true)
        assertTrue(SessionPrefs.addedGamesArt(context))
        assertTrue(SessionPrefs.emulatorArtwork(context))

        SessionPrefs.setAddedGamesArt(context, false)
        SessionPrefs.setEmulatorArtwork(context, false)
        assertFalse(SessionPrefs.addedGamesArt(context))
        assertFalse(SessionPrefs.emulatorArtwork(context))
    }
}
