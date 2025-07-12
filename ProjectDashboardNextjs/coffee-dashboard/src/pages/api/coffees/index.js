// src/pages/api/coffees/index.js
import { getConnection } from '@/lib/db';
import sql from 'mssql';

export default async function handler(req, res) {
    try {
        const pool = await getConnection();

        if (req.method === 'GET') {
            // ดึงข้อมูลกาแฟทั้งหมด
            const result = await pool.request().query('SELECT * FROM Coffees ORDER BY Id DESC');
            res.status(200).json(result.recordset);

        } else if (req.method === 'POST') {
            // เพิ่มกาแฟใหม่
            const { name, origin, price, imageUrl } = req.body;

            if (!name || !origin || !price) {
                return res.status(400).json({ message: 'Name, origin, and price are required.' });
            }

            const result = await pool.request()
                .input('name', sql.NVarChar, name)
                .input('origin', sql.NVarChar, origin)
                .input('price', sql.Decimal(10, 2), price)
                .input('imageUrl', sql.NVarChar, imageUrl || 'https://images.unsplash.com/photo-1511920183353-3c9c13aaa489?auto=format&fit=crop&q=80&w=250') // Default image
                .query('INSERT INTO Coffees (Name, Origin, Price, ImageUrl) VALUES (@name, @origin, @price, @imageUrl)');

            res.status(201).json({ message: 'Coffee added successfully!', data: req.body });

        } else {
            res.setHeader('Allow', ['GET', 'POST']);
            res.status(405).end(`Method ${req.method} Not Allowed`);
        }

    } catch (error) {
        console.error('API Error:', error);
        res.status(500).json({ message: 'Internal Server Error', error: error.message });
    }
}