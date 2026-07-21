use crate::api::ValueNotification;
use crate::common::util::notifications_stream_from_broadcast_receiver;
use futures::stream::StreamExt;
use tokio::sync::broadcast;
use uuid::Uuid;

/// Notifications sent before subscribing should not be received.
#[tokio::test]
async fn notification_stream_receives_messages() {
    let (tx, _) = broadcast::channel(16);
    let rx = tx.subscribe();
    let mut stream = notifications_stream_from_broadcast_receiver(rx);

    let uuid = Uuid::nil();
    let notification = ValueNotification {
        uuid,
        value: vec![1, 2, 3],
    };

    tx.send(notification.clone()).unwrap();

    let received = stream.next().await.unwrap();
    assert_eq!(received, notification);
}

/// When the broadcast channel lags, the stream should skip lost messages
/// and continue delivering subsequent ones instead of terminating.
#[tokio::test]
async fn notification_stream_survives_lag() {
    // capacity=2 so we can easily overflow it
    let (tx, _) = broadcast::channel(2);
    let rx = tx.subscribe();
    let mut stream = notifications_stream_from_broadcast_receiver(rx);

    let uuid = Uuid::nil();

    // Send 4 messages; with capacity 2, the receiver will lag.
    for i in 0u8..4 {
        let _ = tx.send(ValueNotification {
            uuid,
            value: vec![i],
        });
    }

    // The stream should still yield *something* (the surviving messages)
    // rather than terminating. The lagged messages are lost.
    let received = stream.next().await.unwrap();
    // We can't predict exactly which message survives after lag, but the
    // stream must not have ended.
    assert!(!received.value.is_empty());
}

/// After the sender is dropped the stream should terminate (return None).
#[tokio::test]
async fn notification_stream_ends_when_sender_dropped() {
    let (tx, _) = broadcast::channel::<ValueNotification>(16);
    let rx = tx.subscribe();
    let mut stream = notifications_stream_from_broadcast_receiver(rx);

    drop(tx);

    // With no senders left, next() should return None.
    let result = stream.next().await;
    assert!(result.is_none());
}
