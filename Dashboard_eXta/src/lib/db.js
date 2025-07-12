// lib/db.js
import sql from 'mssql';

// อ่านค่า Config จาก Environment Variables ที่ Next.js โหลดให้
const config = {
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    server: process.env.DB_SERVER,
    database: process.env.DB_DATABASE,
    options: {
        encrypt: false, // ตั้งเป็น true หากใช้ Azure SQL
        enableArithAbort: true,
        trustServerCertificate: true,
    },
    port: 1433,
};

// สร้าง Connection Pool เพียงครั้งเดียวและเก็บไว้เพื่อใช้ซ้ำ
// นี่คือ Best Practice สำหรับ Performance ในสภาพแวดล้อม Serverless/Web
let pool;

async function getPool() {
  if (!pool) {
    try {
      // สร้าง Promise ของ pool และเก็บไว้
      // การ connect จะเกิดขึ้นแค่ครั้งแรก
      pool = new sql.ConnectionPool(config).connect();
      console.log('Creating new database connection pool...');
    } catch (err) {
      console.error('Failed to create database pool', err);
      // หากสร้างไม่ได้ ให้โยน error ออกไป
      throw err;
    }
  }
  // คืนค่า Promise ของ pool ที่เชื่อมต่อแล้ว
  return pool;
}

/**
 * ฟังก์ชันสำหรับ Execute SQL Query
 * @param {string} query - คำสั่ง SQL ที่ต้องการรัน
 * @param {Array<{name: string, type: any, value: any}>} params - (Optional) Array ของ Parameters
 * @returns {Promise<Array<any>>} - ผลลัพธ์จาก Query
 */
export async function executeQuery(query, params = []) {
    try {
        // รอให้ pool พร้อมใช้งาน (จะ connect แค่ครั้งแรก)
        const pool = await getPool();

        // สร้าง request จาก pool ที่มีอยู่
        const request = pool.request();

        // เพิ่ม Parameters เข้าไปใน Request
        params.forEach((param) => {
            request.input(param.name, param.type, param.value);
        });

        const result = await request.query(query);
        return result.recordset || [];
    } catch (err) {
        console.error('SQL Execution Error', err);
        // โยน error ต่อเพื่อให้ API route จัดการ
        throw new Error('Failed to execute database query.');
    }
}