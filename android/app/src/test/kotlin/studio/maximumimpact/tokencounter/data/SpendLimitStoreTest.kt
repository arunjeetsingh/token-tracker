package studio.maximumimpact.tokencounter.data

import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SpendLimitStoreTest {

    private fun store() = DataStoreSpendLimitStore(InMemoryPreferencesDataStore())

    @Test
    fun defaultsToNull() = runTest {
        assertNull(store().limitCents.first())
    }

    @Test
    fun setThenRead_roundTrips() = runTest {
        val store = store()
        store.setLimitCents(140_000)
        assertEquals(140_000L, store.limitCents.first())
    }

    @Test
    fun setNull_clearsTheLimit() = runTest {
        val store = store()
        store.setLimitCents(140_000)
        store.setLimitCents(null)
        assertNull(store.limitCents.first())
    }
}
