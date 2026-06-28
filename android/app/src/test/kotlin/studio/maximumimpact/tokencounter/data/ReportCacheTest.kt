package studio.maximumimpact.tokencounter.data

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import studio.maximumimpact.tokencounter.core.DemoData
import studio.maximumimpact.tokencounter.providers.ProviderKind

class ReportCacheTest {

    private fun cache() = DataStoreReportCache(InMemoryPreferencesDataStore())

    @Test
    fun load_returnsNullWhenEmpty() = runTest {
        assertNull(cache().load())
    }

    @Test
    fun save_thenLoad_roundTripsTheReport() = runTest {
        val cache = cache()
        val snapshot = DemoData.snapshot()

        cache.save(snapshot.report, snapshot.orgName)
        val loaded = cache.load()

        assertEquals(snapshot.orgName, loaded?.orgName)
        assertEquals(snapshot.report, loaded?.report)
    }

    @Test
    fun loadAll_mapsLegacySnapshotToAnthropicForUpgradeBootstrap() = runTest {
        val cache = cache()
        val snapshot = DemoData.snapshot()

        cache.save(snapshot.report, snapshot.orgName)
        val loaded = cache.loadAll()

        assertEquals(setOf(ProviderKind.ANTHROPIC), loaded.keys)
        assertEquals(snapshot.orgName, loaded[ProviderKind.ANTHROPIC]?.orgName)
        assertEquals(snapshot.report, loaded[ProviderKind.ANTHROPIC]?.report)
    }

    @Test
    fun clear_removesTheCachedReport() = runTest {
        val cache = cache()
        val snapshot = DemoData.snapshot()
        cache.save(snapshot.report, snapshot.orgName)

        cache.clear()

        assertNull(cache.load())
    }
}
