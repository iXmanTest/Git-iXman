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

// [แก้ไข] ใช้ Backticks (`) เพื่อให้สามารถใช้ ${...} ได้
const serviceName = `${packageJson.name}-service`; 
const serviceDescription = packageJson.description || `Runs the ${packageJson.name} Next.js application.`;

// 2. [สำคัญ] ระบุ Path ไปยัง "ไฟล์ตัวกลาง" (Runner Script) ที่เราสร้างขึ้น
const scriptPath = path.join(__dirname, 'start-production-server.js');

console.log(`[INFO] กำลังตั้งค่า Service: '${serviceName}'`);
console.log(`[INFO] Script ที่จะรัน: ${scriptPath}`);

// 3. สร้าง Object ของ Service
const svc = new Service({
    name: serviceName,
    description: serviceDescription,
    script: scriptPath
});

// 4. สร้าง Event Listener (เหมือนเดิม)
svc.on('install', function () {
    console.log(`✅ '${serviceName}' ติดตั้งสำเร็จ`);
    console.log('กำลังเริ่มต้น Service...');
    svc.start();
});

svc.on('alreadyinstalled', function () {
    console.log(`[INFO] '${serviceName}' ถูกติดตั้งไว้แล้ว`);
});

svc.on('uninstall', function () {
    console.log(`✅ '${serviceName}' ถอนการติดตั้งสำเร็จ`);
});

svc.on('start', function () {
    console.log(`✅ '${serviceName}' เริ่มทำงานสำเร็จ`);
});

svc.on('stop', function () {
    console.log(`✅ '${serviceName}' หยุดทำงานสำเร็จ`);
});

svc.on('error', function (err) {
    console.error(`❌ เกิดข้อผิดพลาดกับ Service:`, err);
});


// 5. รับคำสั่งจาก Command Line (เหมือนเดิม)
const command = process.argv[2];

if (!command) {
    console.log('กรุณาเลือกคำสั่ง: install, uninstall, start, stop, restart');
    return;
}

console.log(`[ACTION] กำลังดำเนินการ: ${command} สำหรับ Service '${serviceName}'`);

switch (command.toLowerCase()) {
    case 'install':
        svc.install();
        break;
    case 'uninstall':
        svc.uninstall();
        break;
    case 'start':
        svc.start();
        break;
    case 'stop':
        svc.stop();
        break;
    case 'restart':
        svc.restart();
        break;
    default:
        console.log('คำสั่งไม่ถูกต้อง. คำสั่งที่ใช้ได้: install, uninstall, start, stop, restart');
}