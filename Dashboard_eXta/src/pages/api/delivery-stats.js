// pages/api/delivery-stats.js
import { executeQuery } from '../../lib/db'; // Import ฟังก์ชันที่เราสร้าง

export default async function handler(req, res) {
  if (req.method === 'GET') {
    try {
      // **สำคัญ:** แก้ไขชื่อตาราง 'YourDeliveryStatsTable' ให้เป็นชื่อตารางจริงของคุณ
      const query = `exec [ExtaNew].[dbo].[DeliveryStats]`;
      
      // รัน query โดยใช้ฟังก์ชันที่ import มา
      const dataFromDb = await executeQuery(query);

      // ส่งข้อมูลที่ได้จาก DB กลับไปเป็น JSON
      res.status(200).json(dataFromDb);

    } catch (error) {
      console.error('API Error:', error);
      res.status(500).json({ message: 'Error fetching data from the database.' });
    }
  } else {
    res.setHeader('Allow', ['GET']);
    res.status(405).end(`Method ${req.method} Not Allowed`);
  }
}