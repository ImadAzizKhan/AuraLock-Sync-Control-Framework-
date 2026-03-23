const admin = require("firebase-admin");
const fs = require("fs"); // File system module

let serviceAccount;

// Check karte hain ke kya hum Render par hain (Render secret files yahan rakhta hai)
if (fs.existsSync("/etc/secrets/firebase-key.json")) {
    serviceAccount = require("/etc/secrets/firebase-key.json");
    console.log("☁️ Running on Render - Using Secret File");
} 
// Agar file nahi mili, toh iska matlab hai server aapke apne laptop par chal raha hai
else {
    serviceAccount = require("./firebase-key.json");
    console.log("💻 Running Locally - Using Local File");
}

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();
console.log("🔥 Firebase Admin Connected Successfully!");

const express = require('express');
const http = require('http');
const { Server } = require('socket.io');

const app = express();
const server = http.createServer(app);

// Enable CORS so your Flutter apps aren't blocked by security rules
// 🚨 UPDATE 1: maxHttpBufferSize add kar diya hai (Limit = 50 MB)
const io = new Server(server, { 
    cors: { origin: "*" },
    maxHttpBufferSize: 5e7 
});

// 👇 1. WEB ROUTE (Bahar nikal diya) 👇
app.get('/love-tap', (req, res) => {
    // Seedha Socket emit karwa dein
    io.emit('vibrate_signal', { 
        type: 'MSG', 
        message: '💖 Boss tapped the locket! She misses you!' 
    });
    
    // Unke phone par browser mein yeh cute sa animated page show hoga
    res.send(`
        <html>
        <head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
        <body style="background-color:#0A0A0A; color:#FF4081; text-align:center; font-family:sans-serif; display:flex; flex-direction:column; justify-content:center; height:100vh; margin:0;">
            <h1 style="font-size:80px; margin:0; animation: pulse 1s infinite;">💖</h1>
            <h2>Love sent to Imad!</h2>
            <p style="color:grey; font-size:14px;">He just felt your heartbeat.</p>
            <style>
              @keyframes pulse {
                0% { transform: scale(1); }
                50% { transform: scale(1.1); }
                100% { transform: scale(1); }
              }
            </style>
        </body>
        </html>
    `);
});

app.get('/ping', (req, res) => {
    res.send('Server is awake and ready! 🚀');
});

io.on('connection', (socket) => {
    console.log('📱 A device connected! ID:', socket.id);

    // This listens for her Poco X7 sending the vibration command
    socket.on('update_status', (data) => {
        console.log("Status changed to:", data.mode);
        // This sends the new mode to EVERYONE connected (including her app)
        io.emit('status_updated', data); 
    });

    socket.on('trigger_vibration', (data) => {
        console.log(`⚡ Command triggered [${data.type}]! Broadcasting...`);
        // Broadcast sends the signal to everyone EXCEPT the sender
        socket.broadcast.emit('vibrate_signal', data);
    });

    // 🚨 UPDATE 2: Media (Image/Voice) Relay Listener
    // Yeh event Sub-Station se photo/audio pakrega aur Boss ko dega
    socket.on('proof_submitted', (data) => {
        if (data.image) {
            console.log('📸 Picture Proof received! Forwarding to Boss App...');
        } else if (data.audio) {
            console.log('🎤 Voice Proof received! Forwarding to Boss App...');
        }
        
        socket.broadcast.emit('proof_submitted', data);
    });

    socket.on('danger_location', (data) => {
        console.log(`📍 Danger Location Update! Lat: ${data.latitude}, Lng: ${data.longitude}`);
        socket.broadcast.emit('danger_location', data);
    });

    socket.on('disconnect', () => {
        console.log('❌ A device disconnected:', socket.id);
    });
});

// Use port 3000 for local testing
const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
    console.log(`🧠 Locket Nervous System running on port ${PORT}`);
});