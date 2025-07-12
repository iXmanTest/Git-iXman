แน่นอนครับ! ด้านล่างนี้คือขั้นตอนและตัวอย่างโค้ดสำหรับการรวม **Next.js (frontend) + Node.js/Express (backend) + MSSQL + Docker + Material UI** ให้อยู่ในโปรเจคเดียว (Monorepo) แบบโฟลเดอร์เดียวกัน

---

## 1. โครงสร้างโปรเจค

```
coffee-dashboard/
├── backend/            # Node.js + Express + MSSQL
│   ├── index.js
│   ├── package.json
│   ├── .env
├── frontend/           # Next.js + Material UI
│   ├── pages/
│   ├── package.json
│   └── ...
├── docker-compose.yml
├── README.md
```

---

## 2. ตัวอย่างโครงสร้างไฟล์

### 2.1 backend/index.js

```javascript name=backend/index.js
require('dotenv').config();
const express = require('express');
const sql = require('mssql');
const cors = require('cors');
const app = express();
const port = 5000;

app.use(express.json());
app.use(cors());

const dbConfig = {
  user: process.env.MSSQL_USER,
  password: process.env.MSSQL_PASSWORD,
  server: process.env.MSSQL_SERVER,
  database: process.env.MSSQL_DATABASE,
  options: {
    encrypt: false,
    trustServerCertificate: true
  }
};

app.get('/api/coffees', async (req, res) => {
  try {
    await sql.connect(dbConfig);
    const result = await sql.query('SELECT * FROM Coffees');
    res.json(result.recordset);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.listen(port, () => {
  console.log(`Server running on port ${port}`);
});
```

### 2.2 backend/.env

```env name=backend/.env
MSSQL_USER=sa
MSSQL_PASSWORD=yourStrong(!)Password
MSSQL_SERVER=mssql
MSSQL_DATABASE=CoffeeDB
```

### 2.3 backend/package.json

```json name=backend/package.json
{
  "name": "backend",
  "version": "1.0.0",
  "main": "index.js",
  "scripts": {
    "start": "node index.js"
  },
  "dependencies": {
    "cors": "^2.8.5",
    "dotenv": "^16.3.1",
    "express": "^4.18.2",
    "mssql": "^10.0.0"
  }
}
```

---

### 2.4 frontend/pages/index.jsx

```jsx name=frontend/pages/index.jsx
import React, { useEffect, useState } from "react";
import { Container, Typography, Grid, Card, CardMedia, CardContent, CircularProgress } from "@mui/material";

export default function Home() {
  const [coffees, setCoffees] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetch("http://localhost:5000/api/coffees")
      .then((res) => res.json())
      .then((data) => {
        setCoffees(data);
        setLoading(false);
      });
  }, []);

  return (
    <Container maxWidth="lg" sx={{ mt: 4 }}>
      <Typography variant="h3" gutterBottom align="center">Coffee Dashboard</Typography>
      {loading ? (
        <CircularProgress />
      ) : (
        <Grid container spacing={4}>
          {coffees.map((coffee) => (
            <Grid item xs={12} sm={6} md={4} key={coffee.id}>
              <Card sx={{ maxWidth: 345, borderRadius: 3, boxShadow: 6 }}>
                <CardMedia
                  component="img"
                  height="180"
                  image={coffee.imageUrl || "/coffee.jpg"}
                  alt={coffee.name}
                />
                <CardContent>
                  <Typography variant="h6">{coffee.name}</Typography>
                  <Typography color="text.secondary">${coffee.price}</Typography>
                </CardContent>
              </Card>
            </Grid>
          ))}
        </Grid>
      )}
    </Container>
  );
}
```

### 2.5 frontend/package.json

```json name=frontend/package.json
{
  "name": "frontend",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start"
  },
  "dependencies": {
    "@emotion/react": "^11.11.1",
    "@emotion/styled": "^11.11.0",
    "@mui/icons-material": "^5.14.0",
    "@mui/material": "^5.14.0",
    "next": "14.2.3",
    "react": "18.2.0",
    "react-dom": "18.2.0"
  }
}
```

---

### 2.6 Dockerfile สำหรับ Backend

```dockerfile name=backend/Dockerfile
FROM node:18
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 5000
CMD ["npm", "start"]
```

### 2.7 Dockerfile สำหรับ Frontend

```dockerfile name=frontend/Dockerfile
FROM node:18
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 3000
CMD ["npm", "run", "dev"]
```

---

### 2.8 docker-compose.yml (รวมทุกอย่าง)

```yaml name=docker-compose.yml
version: '3.9'
services:
  mssql:
    image: mcr.microsoft.com/mssql/server:2022-latest
    container_name: mssql
    environment:
      SA_PASSWORD: "yourStrong(!)Password"
      ACCEPT_EULA: "Y"
    ports:
      - "1433:1433"
    volumes:
      - mssql-data:/var/opt/mssql
  backend:
    build: ./backend
    ports:
      - "5000:5000"
    environment:
      - MSSQL_USER=sa
      - MSSQL_PASSWORD=yourStrong(!)Password
      - MSSQL_SERVER=mssql
      - MSSQL_DATABASE=CoffeeDB
    depends_on:
      - mssql
  frontend:
    build: ./frontend
    ports:
      - "3000:3000"
    depends_on:
      - backend
volumes:
  mssql-data:
```

---

## 3. วิธีใช้งาน

1. เตรียม `Coffees` table ใน MSSQL (รัน SQL ด้านล่างใน SSMS หรือ Azure Data Studio หลัง mssql container ทำงาน)
    ```sql
    CREATE DATABASE CoffeeDB;
    GO
    USE CoffeeDB;
    GO
    CREATE TABLE Coffees (
      id INT PRIMARY KEY IDENTITY(1,1),
      name NVARCHAR(50),
      price FLOAT,
      imageUrl NVARCHAR(255)
    );
    GO
    INSERT INTO Coffees (name, price, imageUrl) VALUES ('Espresso', 60, 'https://images.unsplash.com/photo-1511920170033-f8396924c348');
    ```
2. รัน
    ```bash
    docker-compose up --build
    ```
3. เปิดเบราว์เซอร์ที่ http://localhost:3000

---

## 4. หมายเหตุ

- ปรับแก้ path API หาก deploy จริง (ใช้ env หรือ proxy)
- ตกแต่งหน้าเว็บเพิ่มเติมด้วย MUI ตามตัวอย่าง [MUI Docs](https://mui.com/)
- ใน dev สามารถรันแยก services ได้ (`npm start` ใน backend, `npm run dev` ใน frontend)

---

**ถ้าต้องการไฟล์ README.md หรือตัวอย่างโค้ดส่วนอื่นเพิ่มเติม แจ้งได้เลยครับ!**