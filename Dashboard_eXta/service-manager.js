const { Service } = require('node-windows');
const path = require('path');

// 1. อ่านข้อมูลจาก package.json
let packageJson;
try {
    packageJson = require('./package.json');
} catch (error) {
    console.error('❌ Error: ไม่สามารถอ่านไฟล์ package.json ได้');
    process.exit(1);
}

const serviceName = `${packageJson.name}-service`;
const serviceDescription = packageJson.description || `Runs the ${packageJson.name} Next.js application.`;

// 2. ระบุ Path ไปยัง "ไฟล์ตัวกลาง"
const scriptPath = path.join(__dirname, 'start-production-server.js');

// 3. ✨ [ใหม่] ดึงค่า Port จาก "config" ใน package.json โดยตรง
// นี่เป็นวิธีที่ง่ายและแม่นยำกว่าเดิม
const servicePort = packageJson.config.port || '3000'; // ใช้ 3000 เป็นค่าสำรองถ้าไม่เจอ


console.log(`[INFO] กำลังตั้งค่า Service: '${serviceName}'`);
console.log(`[INFO] Script ที่จะรัน: ${scriptPath}`);
console.log(`[INFO] 💡 Service จะทำงานบน Port: ${servicePort} (จาก package.json > config)`); // <-- แสดง Port ให้เห็น

// 4. สร้าง Object ของ Service พร้อมส่งค่า Port ไปด้วย
const svc = new Service({
    name: serviceName,
    description: 'Port:'+ servicePort+ ' ' +serviceDescription,
    script: scriptPath,
    env: {
        name: 'SERVICE_PORT',
        value: servicePort
    }
});

// 5. สร้าง Event Listener และส่วนที่เหลือ (เหมือนเดิม)
svc.on('install', function () {
    console.log(`✅ '${serviceName}' ติดตั้งสำเร็จ`);
    console.log(`กำลังเริ่มต้น Service บน Port ${servicePort}...`);
    svc.start();
});

svc.on('alreadyinstalled', function () {
    console.log(`[INFO] '${serviceName}' ถูกติดตั้งไว้แล้ว`);
});

svc.on('uninstall', function () {
    console.log(`✅ '${serviceName}' ถอนการติดตั้งสำเร็จ`);
});

svc.on('start', function () {
    console.log(`✅ '${serviceName}' เริ่มทำงานสำเร็จที่ Port: ${servicePort}`);
});

svc.on('stop', function () {
    console.log(`✅ '${serviceName}' หยุดทำงานสำเร็จ`);
});

svc.on('error', function (err) {
    console.error(`❌ เกิดข้อผิดพลาดกับ Service:`, err);
});

// 6. รับคำสั่งจาก Command Line (เหมือนเดิม)
const command = process.argv[2];
if (!command) {
    console.log('กรุณาเลือกคำสั่ง: install, uninstall, start, stop, restart');
    return;
}
console.log(`[ACTION] กำลังดำเนินการ: ${command} สำหรับ Service '${serviceName}'`);
switch (command.toLowerCase()) {
    case 'install': svc.install(); break;
    case 'uninstall': svc.uninstall(); break;
    case 'start': svc.start(); break;
    case 'stop': svc.stop(); break;
    case 'restart': svc.restart(); break;
    default: console.log('คำสั่งไม่ถูกต้อง. คำสั่งที่ใช้ได้: install, uninstall, start, stop, restart');
}

