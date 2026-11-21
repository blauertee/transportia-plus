package one.wafler.transportia

import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.CalendarContract
import android.provider.CalendarContract.Calendars
import android.provider.CalendarContract.Events
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone
import java.util.concurrent.Executors

/**
 * The device's calendars, for adding saved trips to one
 * (`lib/services/calendar_bridge.dart` is the other end).
 *
 * Events are only ever addressed by the id they were created with: nothing
 * here searches a calendar. The one calendar written as a sync adapter is
 * the app's own, which [CalendarContract.ACCOUNT_TYPE_LOCAL] keeps on the
 * phone, and [deleteOwnCalendar] refuses any other.
 */
class CalendarBridge private constructor(
    private val context: Context,
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val CHANNEL = "transportia/calendar"

        /** The account the app's own calendar is filed under. */
        private const val OWN_ACCOUNT_NAME = "Transportia+"

        /** Answered when Android withholds the calendar permission. */
        private const val NOT_PERMITTED = "not_permitted"

        fun register(engine: FlutterEngine, context: Context) {
            MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                .setMethodCallHandler(CalendarBridge(context.applicationContext))
        }
    }

    /** The calendar provider is a database: kept off the UI thread. */
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        worker.execute {
            try {
                val value: Any? = when (call.method) {
                    "listCalendars" -> listCalendars()
                    "readCalendar" -> readCalendar(call.long("id"))
                    "createOwnCalendar" -> createOwnCalendar(
                        call.argument<String>("name")!!,
                        call.argument<Number>("color")!!.toInt(),
                    )
                    "deleteOwnCalendar" -> deleteOwnCalendar(call.long("id"))
                    "insertEvent" -> insertEvent(call)
                    "readEvent" -> readEvent(call.long("id"))
                    "updateEventTitle" -> {
                        updateEventTitle(call.long("id"), call.argument<String>("title")!!)
                        null
                    }
                    "deleteEvent" -> {
                        deleteEvent(call.long("id"))
                        null
                    }
                    else -> {
                        main.post { result.notImplemented() }
                        return@execute
                    }
                }
                main.post { result.success(value) }
            } catch (e: SecurityException) {
                main.post { result.error(NOT_PERMITTED, e.message, null) }
            } catch (e: Exception) {
                main.post { result.error("failed", e.message, null) }
            }
        }
    }

    /** Dart sends small ints as Integer and large ones as Long. */
    private fun MethodCall.long(key: String): Long = argument<Number>(key)!!.toLong()

    private val calendarColumns = arrayOf(
        Calendars._ID,
        Calendars.CALENDAR_DISPLAY_NAME,
        Calendars.ACCOUNT_NAME,
        Calendars.ACCOUNT_TYPE,
        Calendars.CALENDAR_COLOR,
    )

    private fun calendarAt(cursor: android.database.Cursor): Map<String, Any?> = mapOf(
        "id" to cursor.getLong(0),
        "name" to (cursor.getString(1) ?: ""),
        "accountName" to (cursor.getString(2) ?: ""),
        "accountType" to (cursor.getString(3) ?: ""),
        "color" to cursor.getInt(4),
    )

    /** Visible calendars the app may add events to. */
    private fun listCalendars(): List<Map<String, Any?>> {
        val calendars = mutableListOf<Map<String, Any?>>()
        context.contentResolver.query(
            Calendars.CONTENT_URI,
            calendarColumns,
            "${Calendars.VISIBLE} = 1 AND ${Calendars.CALENDAR_ACCESS_LEVEL} >= ?",
            arrayOf(Calendars.CAL_ACCESS_CONTRIBUTOR.toString()),
            null,
        )?.use { cursor ->
            while (cursor.moveToNext()) calendars.add(calendarAt(cursor))
        }
        return calendars
    }

    private fun readCalendar(id: Long): Map<String, Any?>? {
        context.contentResolver.query(
            ContentUris.withAppendedId(Calendars.CONTENT_URI, id),
            calendarColumns,
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) return calendarAt(cursor)
        }
        return null
    }

    /** [uri] as the local account's sync adapter, the only way to make or
     * remove a calendar. */
    private fun asOwnAccount(uri: Uri): Uri = uri.buildUpon()
        .appendQueryParameter(CalendarContract.CALLER_IS_SYNCADAPTER, "true")
        .appendQueryParameter(Calendars.ACCOUNT_NAME, OWN_ACCOUNT_NAME)
        .appendQueryParameter(Calendars.ACCOUNT_TYPE, CalendarContract.ACCOUNT_TYPE_LOCAL)
        .build()

    private fun createOwnCalendar(name: String, color: Int): Long {
        val values = ContentValues().apply {
            put(Calendars.ACCOUNT_NAME, OWN_ACCOUNT_NAME)
            put(Calendars.ACCOUNT_TYPE, CalendarContract.ACCOUNT_TYPE_LOCAL)
            put(Calendars.NAME, name)
            put(Calendars.CALENDAR_DISPLAY_NAME, name)
            put(Calendars.CALENDAR_COLOR, color)
            put(Calendars.CALENDAR_ACCESS_LEVEL, Calendars.CAL_ACCESS_OWNER)
            put(Calendars.OWNER_ACCOUNT, OWN_ACCOUNT_NAME)
            put(Calendars.VISIBLE, 1)
            put(Calendars.SYNC_EVENTS, 1)
            put(Calendars.CALENDAR_TIME_ZONE, TimeZone.getDefault().id)
        }
        val created = context.contentResolver.insert(asOwnAccount(Calendars.CONTENT_URI), values)
            ?: throw IllegalStateException("The calendar provider made no calendar")
        return ContentUris.parseId(created)
    }

    /** Deletes calendar [id] only if it is the app's own; false otherwise. */
    private fun deleteOwnCalendar(id: Long): Boolean {
        val uri = ContentUris.withAppendedId(Calendars.CONTENT_URI, id)
        val isOwn = context.contentResolver.query(
            uri,
            arrayOf(Calendars.ACCOUNT_NAME, Calendars.ACCOUNT_TYPE),
            null,
            null,
            null,
        )?.use { cursor ->
            cursor.moveToFirst() &&
                cursor.getString(0) == OWN_ACCOUNT_NAME &&
                cursor.getString(1) == CalendarContract.ACCOUNT_TYPE_LOCAL
        } ?: false
        if (!isOwn) return false
        return context.contentResolver.delete(asOwnAccount(uri), null, null) > 0
    }

    private fun insertEvent(call: MethodCall): Long {
        val values = ContentValues().apply {
            put(Events.CALENDAR_ID, call.long("calendarId"))
            put(Events.TITLE, call.argument<String>("title"))
            put(Events.DESCRIPTION, call.argument<String>("description"))
            put(Events.EVENT_LOCATION, call.argument<String>("location"))
            put(Events.DTSTART, call.long("start"))
            put(Events.DTEND, call.long("end"))
            put(Events.EVENT_TIMEZONE, TimeZone.getDefault().id)
            put(Events.AVAILABILITY, Events.AVAILABILITY_BUSY)
        }
        val created = context.contentResolver.insert(Events.CONTENT_URI, values)
            ?: throw IllegalStateException("The calendar provider made no event")
        return ContentUris.parseId(created)
    }

    private fun readEvent(id: Long): Map<String, Any?>? {
        context.contentResolver.query(
            ContentUris.withAppendedId(Events.CONTENT_URI, id),
            arrayOf(
                Events.CALENDAR_ID,
                Events.TITLE,
                Events.DESCRIPTION,
                Events.DTSTART,
                Events.DTEND,
                Events.DELETED,
            ),
            null,
            null,
            null,
        )?.use { cursor ->
            if (!cursor.moveToFirst()) return null
            return mapOf(
                "calendarId" to cursor.getLong(0),
                "title" to (cursor.getString(1) ?: ""),
                "description" to (cursor.getString(2) ?: ""),
                "start" to cursor.getLong(3),
                "end" to cursor.getLong(4),
                "deleted" to (cursor.getInt(5) != 0),
            )
        }
        return null
    }

    private fun updateEventTitle(id: Long, title: String) {
        val values = ContentValues().apply { put(Events.TITLE, title) }
        context.contentResolver.update(
            ContentUris.withAppendedId(Events.CONTENT_URI, id),
            values,
            null,
            null,
        )
    }

    private fun deleteEvent(id: Long) {
        context.contentResolver.delete(
            ContentUris.withAppendedId(Events.CONTENT_URI, id),
            null,
            null,
        )
    }
}
