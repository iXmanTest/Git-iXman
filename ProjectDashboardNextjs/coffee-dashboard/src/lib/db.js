// src/lib/db.js

import sql from 'mssql';

const dbConfig = {
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  server: process.env.DB_HOST,
  port: parseInt(process.env.DB_PORT, 10),
  database: process.env.DB_DATABASE,
  options: {
    encrypt: false,
    trustServerCertificate: true,
  },
  pool: { // เพิ่มการตั้งค่า pool
    max: 10,
    min: 0,
    idleTimeoutMillis: 30000
  }
};

// **หัวใจของการแก้ไข:** สร้างตัวแปร pool ไว้ แต่ยังไม่ connect
let poolPromise = null;

async function getConnection() {
  // ถ้ายังไม่เคยสร้าง promise หรือ promise มีปัญหา ให้สร้างใหม่
  if (!poolPromise) {
    console.log('🔵 Creating new database connection pool...');
    poolPromise = new sql.ConnectionPool(dbConfig)
      .connect()
      .then(pool => {
        console.log('✅ Database connection pool created successfully.');
        // ดักจับ error ที่อาจจะเกิดขึ้นกับ pool ในภายหลัง
        pool.on('error', err => {
          console.error('❌ Database pool error:', err);
          // เมื่อเกิด error ให้เคลียร์ pool promise เพื่อให้ครั้งต่อไปสร้างใหม่
          poolPromise = null;
        });
        return pool;
      })
      .catch(err => {
        console.error('❌ Failed to create database connection pool:', err);
        // เคลียร์ pool promise เพื่อให้ครั้งต่อไปพยายามสร้างใหม่
        poolPromise = null; 
        // โยน error ออกไปให้ caller จัดการ
        throw err;
      });
  }
  
  // คืนค่า promise ของ pool
  return poolPromise;
}

// ฟังก์ชัน executeQuery ไม่ต้องแก้ไข
export async function executeQuery(query, params = {}) {
  try {
    const pool = await getConnection();
    const request = pool.request();
    // (ส่วนการจัดการ params ถ้ามี)
    const result = await request.query(query);
    return result.recordset;
  } catch (err) {
    console.error('SQL execution error', err);
    // สร้าง error ใหม่ที่มีข้อมูลชัดเจนขึ้น
    throw new Error('Failed to execute database query.'); 
  }
}