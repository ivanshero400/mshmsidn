package fajr.din.hk

import android.content.Context
import java.util.Calendar

/**
 * Native, self-contained adhkar source for the home-screen adhkar widget.
 *
 * The widget shows the set appropriate for the current time (morning before
 * noon, evening after) and rotates through its entries over the day so each
 * refresh surfaces a different dhikr "according to its time". Tapping the
 * widget opens the in-app adhkar screen with the matching set — the chosen
 * type is persisted to SharedPreferences so Flutter can pick it up.
 */
object AdhkarStore {

    /** SharedPreferences key (Flutter-prefixed) the adhkar screen reads. */
    const val PREF_TYPE_KEY = "flutter.adhkar_widget_type"

    data class Item(val text: String, val count: String = "", val source: String = "")

    private val morning = listOf(
        Item(
            "اللَّهُ لَا إِلَٰهَ إِلَّا هُوَ الْحَيُّ الْقَيُّومُ، لَا تَأْخُذُهُ سِنَةٌ وَلَا نَوْمٌ، لَهُ مَا فِي السَّمَاوَاتِ وَمَا فِي الْأَرْضِ، وَهُوَ الْعَلِيُّ الْعَظِيمُ",
            source = "آية الكرسي — من قالها حين يصبح أُجير حتى يمسي",
        ),
        Item(
            "أَصْبَحْنَا وَأَصْبَحَ الْمُلْكُ لِلَّهِ، وَالْحَمْدُ لِلَّهِ، لَا إِلَٰهَ إِلَّا اللَّهُ وَحْدَهُ لَا شَرِيكَ لَهُ، لَهُ الْمُلْكُ وَلَهُ الْحَمْدُ وَهُوَ عَلَىٰ كُلِّ شَيْءٍ قَدِيرٌ",
            source = "رواه مسلم",
        ),
        Item(
            "اللَّهُمَّ بِكَ أَصْبَحْنَا، وَبِكَ أَمْسَيْنَا، وَبِكَ نَحْيَا، وَبِكَ نَمُوتُ، وَإِلَيْكَ النُّشُورُ",
            source = "رواه الترمذي",
        ),
        Item(
            "اللَّهُمَّ أَنْتَ رَبِّي لَا إِلَٰهَ إِلَّا أَنْتَ، خَلَقْتَنِي وَأَنَا عَبْدُكَ، أَبُوءُ لَكَ بِنِعْمَتِكَ عَلَيَّ وَأَبُوءُ بِذَنْبِي فَاغْفِرْ لِي فَإِنَّهُ لَا يَغْفِرُ الذُّنُوبَ إِلَّا أَنْتَ",
            source = "سيد الاستغفار — رواه البخاري",
        ),
        Item(
            "رَضِيتُ بِاللَّهِ رَبًّا، وَبِالْإِسْلَامِ دِينًا، وَبِمُحَمَّدٍ ﷺ نَبِيًّا",
            count = "×٣",
            source = "رواه أبو داود",
        ),
        Item(
            "حَسْبِيَ اللَّهُ لَا إِلَٰهَ إِلَّا هُوَ، عَلَيْهِ تَوَكَّلْتُ، وَهُوَ رَبُّ الْعَرْشِ الْعَظِيمِ",
            count = "×٧",
            source = "رواه أبو داود",
        ),
        Item(
            "بِسْمِ اللَّهِ الَّذِي لَا يَضُرُّ مَعَ اسْمِهِ شَيْءٌ فِي الْأَرْضِ وَلَا فِي السَّمَاءِ، وَهُوَ السَّمِيعُ الْعَلِيمُ",
            count = "×٣",
            source = "رواه أبو داود والترمذي",
        ),
        Item(
            "سُبْحَانَ اللَّهِ وَبِحَمْدِهِ",
            count = "×١٠٠",
            source = "حُطّت خطاياه وإن كانت مثل زبد البحر",
        ),
    )

    private val evening = listOf(
        Item(
            "اللَّهُ لَا إِلَٰهَ إِلَّا هُوَ الْحَيُّ الْقَيُّومُ، لَا تَأْخُذُهُ سِنَةٌ وَلَا نَوْمٌ، لَهُ مَا فِي السَّمَاوَاتِ وَمَا فِي الْأَرْضِ، وَهُوَ الْعَلِيُّ الْعَظِيمُ",
            source = "آية الكرسي — من قالها حين يمسي أُجير حتى يصبح",
        ),
        Item(
            "أَمْسَيْنَا وَأَمْسَى الْمُلْكُ لِلَّهِ، وَالْحَمْدُ لِلَّهِ، لَا إِلَٰهَ إِلَّا اللَّهُ وَحْدَهُ لَا شَرِيكَ لَهُ، لَهُ الْمُلْكُ وَلَهُ الْحَمْدُ وَهُوَ عَلَىٰ كُلِّ شَيْءٍ قَدِيرٌ",
            source = "رواه مسلم",
        ),
        Item(
            "اللَّهُمَّ بِكَ أَمْسَيْنَا، وَبِكَ أَصْبَحْنَا، وَبِكَ نَحْيَا، وَبِكَ نَمُوتُ، وَإِلَيْكَ الْمَصِيرُ",
            source = "رواه الترمذي",
        ),
        Item(
            "أَعُوذُ بِكَلِمَاتِ اللَّهِ التَّامَّاتِ مِنْ شَرِّ مَا خَلَقَ",
            count = "×٣",
            source = "من قالها لم يضره شيء — رواه مسلم",
        ),
        Item(
            "اللَّهُمَّ أَنْتَ رَبِّي لَا إِلَٰهَ إِلَّا أَنْتَ، خَلَقْتَنِي وَأَنَا عَبْدُكَ، أَبُوءُ لَكَ بِنِعْمَتِكَ عَلَيَّ وَأَبُوءُ بِذَنْبِي فَاغْفِرْ لِي فَإِنَّهُ لَا يَغْفِرُ الذُّنُوبَ إِلَّا أَنْتَ",
            source = "سيد الاستغفار — رواه البخاري",
        ),
        Item(
            "رَضِيتُ بِاللَّهِ رَبًّا، وَبِالْإِسْلَامِ دِينًا، وَبِمُحَمَّدٍ ﷺ نَبِيًّا",
            count = "×٣",
            source = "رواه أبو داود",
        ),
        Item(
            "بِسْمِ اللَّهِ الَّذِي لَا يَضُرُّ مَعَ اسْمِهِ شَيْءٌ فِي الْأَرْضِ وَلَا فِي السَّمَاءِ، وَهُوَ السَّمِيعُ الْعَلِيمُ",
            count = "×٣",
            source = "رواه أبو داود والترمذي",
        ),
        Item(
            "سُبْحَانَ اللَّهِ وَبِحَمْدِهِ",
            count = "×١٠٠",
            source = "حُطّت خطاياه وإن كانت مثل زبد البحر",
        ),
    )

    /** "morning" before noon, otherwise "evening". */
    fun currentType(): String {
        val hour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
        return if (hour < 12) "morning" else "evening"
    }

    fun titleFor(type: String): String =
        if (type == "evening") "أذكار المساء" else "أذكار الصباح"

    /** The dhikr to surface right now — rotates through the set every ~20 min. */
    fun currentItem(type: String): Item {
        val list = if (type == "evening") evening else morning
        val cal = Calendar.getInstance()
        val minutesOfDay = cal.get(Calendar.HOUR_OF_DAY) * 60 + cal.get(Calendar.MINUTE)
        val index = (minutesOfDay / 20) % list.size
        return list[index]
    }

    /** Persist the type so the Flutter adhkar screen opens the matching set. */
    fun persistType(context: Context, type: String) {
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .edit().putString(PREF_TYPE_KEY, type).apply()
    }
}
