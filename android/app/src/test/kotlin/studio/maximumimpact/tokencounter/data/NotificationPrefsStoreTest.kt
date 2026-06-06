package studio.maximumimpact.tokencounter.data

import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class NotificationPrefsStoreTest {

    private fun store() = DataStoreNotificationPrefsStore(InMemoryPreferencesDataStore())

    @Test
    fun alertEnabled_defaultsFalse() = runTest {
        assertFalse(store().alertEnabled.first())
    }

    @Test
    fun setAlertEnabled_roundTrips() = runTest {
        val store = store()
        store.setAlertEnabled(true)
        assertTrue(store.alertEnabled.first())
        store.setAlertEnabled(false)
        assertFalse(store.alertEnabled.first())
    }

    @Test
    fun lastAlertedMonth_roundTripsAndClears() = runTest {
        val store = store()
        assertNull(store.getLastAlertedMonth())
        store.setLastAlertedMonth("2026-06")
        assertEquals("2026-06", store.getLastAlertedMonth())
        store.setLastAlertedMonth(null)
        assertNull(store.getLastAlertedMonth())
    }
}
