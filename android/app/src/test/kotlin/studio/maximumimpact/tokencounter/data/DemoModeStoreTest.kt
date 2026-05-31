package studio.maximumimpact.tokencounter.data

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DemoModeStoreTest {

    private fun store() = DataStoreDemoModeStore(InMemoryPreferencesDataStore())

    @Test
    fun defaultsToInactive() = runTest {
        assertFalse(store().isActive())
    }

    @Test
    fun setActive_persistsAndCanBeCleared() = runTest {
        val store = store()
        store.setActive(true)
        assertTrue(store.isActive())
        store.setActive(false)
        assertFalse(store.isActive())
    }
}
