//**ไฟล์: `start-production-server.js`**
// ไฟล์นี้ทำหน้าที่เป็น "ตัวกลาง" เพื่อให้ Windows Service
// สามารถรันคำสั่ง `next start` ได้

const { exec } = require('child_process');
const path = require('path');

// คำสั่งที่ต้องการให้รัน คือการเริ่ม production server ของ Next.js
const command = 'npm run start ';

// ระบุ working directory เป็น root ของโปรเจกต์ปัจจุบัน
const options = {
    cwd: path.resolve(__dirname)
};

console.log(`[Service Runner] กำลังเริ่มต้น Next.js Production Server...`);
console.log(`[Service Runner] คำสั่ง: ${command}`);
console.log(`[Service Runner] ใน Directory: ${options.cwd}`);

// สั่งรันคำสั่ง
const serverProcess = exec(command, options);

// console.log(serverProcess);

// ส่ง log จาก process ที่รัน (next start) ออกมายัง log ของ service
// ทำให้เราสามารถดู log ได้ว่า server ทำงานปกติหรือไม่
serverProcess.stdout.on('data', (data) => {
    console.log(data.toString());
});

serverProcess.stderr.on('data', (data) => {
    console.error(data.toString());
});

serverProcess.on('exit', (code) => {
    console.log(`[Service Runner] Next.js server process หยุดทำงานด้วย code: ${code}`);
});