package com.twiliovoicereactnative;

import java.net.URLDecoder;
import java.security.SecureRandom;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;

import android.annotation.SuppressLint;
import android.app.Notification;
import android.app.PendingIntent;
import android.content.ContentResolver;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Color;
import android.media.AudioAttributes;
import android.net.Uri;
import android.widget.RemoteViews;

import androidx.annotation.NonNull;
import androidx.core.app.NotificationChannelCompat;
import androidx.core.app.NotificationChannelGroupCompat;
import androidx.core.app.NotificationCompat;
import androidx.core.app.NotificationManagerCompat;
import androidx.core.app.Person;

import com.twilio.voice.CallInvite;

import static com.twiliovoicereactnative.Constants.VOICE_CHANNEL_DEFAULT_IMPORTANCE;
import static com.twiliovoicereactnative.Constants.VOICE_CHANNEL_HIGH_IMPORTANCE;
import static com.twiliovoicereactnative.Constants.VOICE_CHANNEL_LOW_IMPORTANCE;
import static com.twiliovoicereactnative.VoiceNotificationReceiver.constructMessage;

import com.twiliovoicereactnative.CallRecordDatabase.CallRecord;

class NotificationUtility {
  private static final SecureRandom secureRandom = new SecureRandom();

  public static int createNotificationIdentifier() {
    return (secureRandom.nextInt() & 0x7FFFFFFF) + 1; // prevent 0 as an id
  }

  public static Notification createIncomingCallNotification(@NonNull Context context,
                                                            @NonNull final CallRecord callRecord,
                                                            @NonNull final String channelImportance) {
    final int smallIconResId = getSmallIconResource(context);
    final Bitmap icon = constructBitmap(context, R.drawable.ic_call_end_white_24dp);
    final Person incomingCaller = new Person.Builder()
      .setName(getDisplayName(callRecord.getCallInvite()))
      .build();

    Intent foregroundIntent = constructMessage(
      context,
      Constants.ACTION_FOREGROUND_AND_DEPRIORITIZE_INCOMING_CALL_NOTIFICATION,
      Objects.requireNonNull(VoiceApplicationProxy.getMainActivityClass()),
      callRecord.getUuid());
    PendingIntent piForegroundIntent = constructPendingIntentForActivity(context, foregroundIntent);

    Intent rejectIntent = constructMessage(
      context,
      Constants.ACTION_REJECT_CALL,
      VoiceNotificationReceiver.class,
      callRecord.getUuid());
    PendingIntent piRejectIntent = constructPendingIntentForReceiver(context, rejectIntent);

    Intent acceptIntent = constructMessage(
      context,
      Constants.ACTION_ACCEPT_CALL,
      Objects.requireNonNull(VoiceApplicationProxy.getMainActivityClass()),
      callRecord.getUuid());
    PendingIntent piAcceptIntent = constructPendingIntentForActivity(context, acceptIntent);

    return constructNotificationBuilder(context, channelImportance)
      .setSmallIcon(smallIconResId)
      .setLargeIcon(icon)
      .setCategory(Notification.CATEGORY_CALL)
      .setAutoCancel(true)
      .setContentIntent(piForegroundIntent)
      .setFullScreenIntent(piForegroundIntent, true)
      .addPerson(incomingCaller)
      .setStyle(NotificationCompat.CallStyle.forIncomingCall(
        incomingCaller, piRejectIntent, piAcceptIntent))
      .build();
  }

  public static Notification createCallAnsweredNotificationWithLowImportance(@NonNull Context context,
                                                                             @NonNull final CallRecord callRecord) {
    final int smallIconResId = getSmallIconResource(context);
    final Person activeCaller = new Person.Builder()
      .setName(getDisplayName(callRecord.getCallInvite()))
      .build();

    Intent foregroundIntent = constructMessage(
      context,
      Constants.ACTION_PUSH_APP_TO_FOREGROUND,
      Objects.requireNonNull(VoiceApplicationProxy.getMainActivityClass()),
      callRecord.getUuid());
    PendingIntent piForegroundIntent = constructPendingIntentForActivity(context, foregroundIntent);

    Intent endCallIntent = constructMessage(
      context,
      Constants.ACTION_CALL_DISCONNECT,
      VoiceNotificationReceiver.class,
      callRecord.getUuid());
    PendingIntent piEndCallIntent = constructPendingIntentForReceiver(context, endCallIntent);

    return constructNotificationBuilder(context, Constants.VOICE_CHANNEL_LOW_IMPORTANCE)
      .setSmallIcon(smallIconResId)
      .setCategory(Notification.CATEGORY_CALL)
      .setAutoCancel(false)
      .setContentIntent(piForegroundIntent)
      .setFullScreenIntent(piForegroundIntent, true)
      .setOngoing(true)
      .addPerson(activeCaller)
      .setStyle(NotificationCompat.CallStyle.forOngoingCall(activeCaller, piEndCallIntent))
      .build();
  }

  public static Notification createOutgoingCallNotificationWithLowImportance(@NonNull Context context,
                                                                             @NonNull final CallRecord callRecord) {
    final int smallIconResId = getSmallIconResource(context);
    final Person activeCaller = new Person.Builder()
      .setName("outgoing call")
      .build();

    Intent foregroundIntent = constructMessage(
      context,
      Constants.ACTION_PUSH_APP_TO_FOREGROUND,
      Objects.requireNonNull(VoiceApplicationProxy.getMainActivityClass()),
      callRecord.getUuid());
    PendingIntent piForegroundIntent = constructPendingIntentForActivity(context, foregroundIntent);

    Intent endCallIntent = constructMessage(
      context,
      Constants.ACTION_CALL_DISCONNECT,
      VoiceNotificationReceiver.class,
      callRecord.getUuid());
    PendingIntent piEndCallIntent = constructPendingIntentForReceiver(context, endCallIntent);

    return constructNotificationBuilder(context, Constants.VOICE_CHANNEL_LOW_IMPORTANCE)
      .setSmallIcon(smallIconResId)
      .setCategory(Notification.CATEGORY_CALL)
      .setAutoCancel(false)
      .setContentIntent(piForegroundIntent)
      .setFullScreenIntent(piForegroundIntent, true)
      .setOngoing(true)
      .addPerson(activeCaller)
      .setStyle(NotificationCompat.CallStyle.forOngoingCall(activeCaller, piEndCallIntent))
      .build();
  }

  public static void createNotificationChannels(@NonNull Context context) {
    NotificationManagerCompat notificationManager = NotificationManagerCompat.from(context);
    notificationManager.createNotificationChannelGroup(
      new NotificationChannelGroupCompat.Builder(Constants.VOICE_CHANNEL_GROUP)
        .setName("Twilio Voice").build());

    for (String channelId:
      new String[]{
        VOICE_CHANNEL_HIGH_IMPORTANCE,
        VOICE_CHANNEL_DEFAULT_IMPORTANCE,
        VOICE_CHANNEL_LOW_IMPORTANCE}) {
      notificationManager.createNotificationChannel(
        createNotificationChannel(context, channelId));
    }
  }

  public static void destroyNotificationChannels(@NonNull Context context) {
    NotificationManagerCompat notificationManager = NotificationManagerCompat.from(context);
    notificationManager.deleteNotificationChannelGroup(Constants.VOICE_CHANNEL_GROUP);
  }

  private static NotificationChannelCompat createNotificationChannel(@NonNull Context context,
                                                                     @NonNull final String voiceChannelId) {
    final int notificationImportance = getChannelImportance(voiceChannelId);
    NotificationChannelCompat.Builder voiceChannelBuilder =
      new NotificationChannelCompat.Builder(voiceChannelId, notificationImportance)
        .setName("Primary Voice Channel")
        .setLightColor(Color.GREEN)
        .setGroup(Constants.VOICE_CHANNEL_GROUP);
    // low-importance notifications don't have sound
    if (!Constants.VOICE_CHANNEL_LOW_IMPORTANCE.equals(voiceChannelId)) {
      // set audio attributes for channel
      Uri soundUri = provideResourceSilent_wav(context);
      AudioAttributes audioAttributes = new AudioAttributes.Builder()
        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
        .setUsage(AudioAttributes.USAGE_NOTIFICATION)
        .build();
      voiceChannelBuilder.setSound(soundUri, audioAttributes);
    }
    return voiceChannelBuilder.build();
  }

  private static int getChannelImportance(@NonNull final String voiceChannel) {
    final Map<String, Integer> importanceMapping = Map.of(
      Constants.VOICE_CHANNEL_HIGH_IMPORTANCE, NotificationManagerCompat.IMPORTANCE_HIGH,
      Constants.VOICE_CHANNEL_DEFAULT_IMPORTANCE, NotificationManagerCompat.IMPORTANCE_DEFAULT,
      Constants.VOICE_CHANNEL_LOW_IMPORTANCE, NotificationManagerCompat.IMPORTANCE_LOW);
    return Objects.requireNonNull(importanceMapping.get(voiceChannel));
  }

  private static String getChannel(@NonNull Context context, @NonNull final String voiceChannelId) {
    // construct channel if it has not been created
    NotificationManagerCompat notificationManager = NotificationManagerCompat.from(context);

    if (null == notificationManager.getNotificationChannel(voiceChannelId)) {
      createNotificationChannels(context);
    }
    return voiceChannelId;
  }

  private static String getDisplayName(@NonNull CallInvite callInvite) {
    final String title = callInvite.getFrom();
    Map<String, String> customParameters = callInvite.getCustomParameters();
    // If "displayName" is passed as a custom parameter in the TwiML application,
    // it will be used as the caller name.
    if (customParameters.get(Constants.DISPLAY_NAME) != null) {
      return URLDecoder.decode(customParameters.get(Constants.DISPLAY_NAME).replaceAll("\\+", "%20"));
    } else if (title.startsWith("client:")) {
      return title.replaceFirst("client:", "");
    }
    return title;
  }

  private static String getContentBanner(@NonNull Context context) {
    return context.getString(R.string.app_name) + Constants.NOTIFICATION_BANNER;
  }

  private static PendingIntent constructPendingIntentForActivity(@NonNull Context context,
                                                                 @NonNull final Intent intent) {
    return PendingIntent.getActivity(
      context.getApplicationContext(),
      0,
      intent,
      PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
  }

  private static PendingIntent constructPendingIntentForReceiver(@NonNull Context context,
                                                                 @NonNull final Intent intent) {
    return PendingIntent.getBroadcast(
      context.getApplicationContext(),
      0,
      intent,
      PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
  }

  private static NotificationCompat.Builder constructNotificationBuilder(
    @NonNull Context context,
    @NonNull final String channelImportance) {
    return new NotificationCompat.Builder(context,
        getChannel(context.getApplicationContext(),
          channelImportance));
  }

  @SuppressLint("DiscouragedApi")
  private static int getSmallIconResource(@NonNull Context context) {
    return context.getResources().getIdentifier(
      "ic_notification",
      "drawable",
      context.getPackageName());
  }

  private static Bitmap constructBitmap(@NonNull Context context, final int resId) {
    return BitmapFactory.decodeResource(context.getResources(), resId);
  }

  static Uri provideResourceSilent_wav(@NonNull Context context) {
    return provideResource(context, R.raw.silent);
  }

  private static Uri provideResource(@NonNull Context context, int id) {
    return (new Uri.Builder()
      .scheme(ContentResolver.SCHEME_ANDROID_RESOURCE)
      .authority(context.getResources().getResourcePackageName(id))
      .appendPath(String.valueOf(id))
    ).build();
  }
}
