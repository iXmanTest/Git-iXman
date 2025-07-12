# Dockerfile

# =========================================
# Stage 1: Dependency Installation (deps)
# =========================================
# Stage นี้มีหน้าที่เดียวคือติดตั้ง node_modules
# การแยก stage นี้ออกมาช่วยให้ Docker cache layer นี้ไว้ได้
# ทำให้การ build ครั้งต่อไปเร็วขึ้นมาก ถ้า package.json ไม่ได้เปลี่ยน
FROM node:18-alpine AS deps

# สำหรับ Alpine linux บางครั้งต้องการตัวนี้สำหรับบาง package
RUN apk add --no-cache libc6-compat

# กำหนด Working Directory เป็น /app (สำคัญมาก)
WORKDIR /app

# Copy เฉพาะไฟล์ที่จำเป็นสำหรับการติดตั้ง dependencies
COPY package.json package-lock.json ./

# ติดตั้ง dependencies ทั้งหมด (รวม devDependencies)
# ใช้ npm ci เพื่อความเร็วและความแม่นยำในการ build ตาม lock file
RUN npm ci


# =========================================
# Stage 2: Build the Application (builder)
# =========================================
# Stage นี้จะใช้ผลลัพธ์จาก stage 'deps' มา build โปรเจกต์
FROM node:18-alpine AS builder

# กำหนด Working Directory เป็น /app (ต้องตรงกับ stage ก่อนหน้า)
WORKDIR /app

# Copy node_modules ที่ติดตั้งเสร็จแล้วจาก stage 'deps'
# คำสั่งนี้จะทำงานถูกต้อง เพราะตอนนี้ path ตรงกันแล้ว
COPY --from=deps /app/node_modules ./node_modules

# Copy โค้ดโปรเจกต์ทั้งหมดเข้ามา
COPY . .

# รันคำสั่ง build ของ Next.js
RUN npm run build


# =========================================
# Stage 3: Production Runner
# =========================================
# Stage สุดท้ายที่จะใช้รันแอปพลิเคชันจริง
# เราจะสร้าง image ใหม่จาก base ที่สะอาด และ copy เฉพาะไฟล์ที่จำเป็นมา
# ทำให้ image สุดท้ายมีขนาดเล็กและปลอดภัย
FROM node:18-alpine AS runner

# กำหนด Working Directory เป็น /app
WORKDIR /app

# กำหนด Environment เป็น production
ENV NODE_ENV production

# สร้าง user และ group ใหม่เพื่อไม่ให้รันแอปด้วยสิทธิ์ root (เพื่อความปลอดภัย)
RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

# Copy ไฟล์ที่จำเป็นสำหรับการรันในโหมด production จาก stage 'builder'
COPY --from=builder /app/public ./public
COPY --from=builder /app/.next ./.next
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./package.json

# เปลี่ยนเจ้าของไฟล์ทั้งหมดเป็น user ที่เราสร้างขึ้น
RUN chown -R nextjs:nodejs /app/.next
USER nextjs

# เปิด Port ที่ Next.js จะรัน
EXPOSE 3000

# คำสั่งสำหรับเริ่มการทำงานของ Server
# ตัวอย่าง: "next start"
# ให้ตรวจสอบ script "start" ใน package.json ของคุณ
CMD ["npm", "start"]