// web/firebase-messaging-sw.js

// Use compat imports for compatibility with FlutterFire web messaging
importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-messaging-compat.js');

// REPLACE with your config (public; safe to expose)
// For Firebase JS SDK v7.20.0 and later, measurementId is optional
const firebaseConfig = {
  apiKey: "AIzaSyB1CPrTeHlm5N4IR5VvvXru-Z_yOMYYYfs",
  authDomain: "batchwise-2bd30.firebaseapp.com",
  projectId: "batchwise-2bd30",
  storageBucket: "batchwise-2bd30.firebasestorage.app",
  messagingSenderId: "13416100959",
  appId: "1:13416100959:web:0500ce0991aa206e1097ea",
  measurementId: "G-5ZSKCND26H"
};

// Retrieve messaging
const messaging = firebase.messaging();

// Optional: customize notification click
self.addEventListener('notificationclick', function(event) {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(clientList => {
      for (const client of clientList) {
        if ('focus' in client) return client.focus();
      }
      if (clients.openWindow) return clients.openWindow('/');
    })
  );
});