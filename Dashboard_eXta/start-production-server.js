const { exec } = require('child_process');
const path = require('path');

// 1. รับค่า Port จาก Environment Variable ที่ Service ส่งมาให้เท่านั้น
//    วิธีนี้ทำให้สคริปต์นี้พึ่งพาข้อมูลจาก service-manager โดยตรง
const port = process.env.SERVICE_PORT;

// 2. ตรวจสอบว่าได้รับ Port มาหรือไม่ ถ้าไม่ได้รับ ให้หยุดทำงานและแจ้งข้อผิดพลาด
if (!port) {
    console.error('[Service Runner] ❌ CRITICAL ERROR: ไม่ได้รับค่า Port จาก service-manager.js');
    // ออกจากโปรแกรมด้วย error code เพื่อให้ Service รู้ว่าเกิดข้อผิดพลาด
    process.exit(1);
}

// 2. [สำคัญ] สร้าง Path เต็มไปยังไฟล์ next.cmd
//    วิธีนี้จะทำให้ Service หาคำสั่ง 'next' เจอเสมอ ไม่ว่า PATH ของระบบจะเป็นอย่างไร
const nextExecutable = path.join(__dirname, 'node_modules', '.bin', 'next');

// 3. สร้างคำสั่งสุดท้ายโดยใช้ "Path เต็ม"
//    เราใส่เครื่องหมาย " " ครอบ Path ไว้เพื่อป้องกันปัญหาถ้าชื่อโฟลเดอร์มีเว้นวรรค
const command = `"${nextExecutable}" start -p ${port}`;

// 4. ตั้งค่า working directory (เหมือนเดิม)
const options = {
    cwd: path.resolve(__dirname)
};

// 5. แสดง Log การทำงานที่ถูกต้อง
console.log(`[Service Runner] 💡 ได้รับค่า Port จาก Service: ${port}`);
console.log(`[Service Runner] กำลังเริ่มต้น Next.js Production Server...`);
console.log(`[Service Runner] ✅ คำสั่งที่จะรัน: ${command}`); // <-- ตรวจสอบว่าคำสั่งนี้ถูกต้อง
console.log(`[Service Runner] ใน Directory: ${options.cwd}`);

// 6. สั่งรันคำสั่ง (เหมือนเดิม)
const serverProcess = exec(command, options);

serverProcess.stdout.on('data', (data) => {
    console.log(data.toString());
});

serverProcess.stderr.on('data', (data) => {
    // แยก error ที่ไม่ใช่แค่คำเตือนปกติ
    const errorString = data.toString();
    if (errorString.toLowerCase().includes('error')) {
      console.error(`[Service Runner] ❌ NEXT.JS ERROR:\n${errorString}`);
    } else {
      console.warn(`[Service Runner] ⚠️ NEXT.JS STDERR:\n${errorString}`);
    }
});

serverProcess.on('exit', (code) => {
    console.log(`[Service Runner] Next.js server process หยุดทำงานด้วย code: ${code}`);
});