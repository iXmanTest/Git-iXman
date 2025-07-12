import { useState, useEffect, useMemo } from 'react';
import {  Container,  Typography,  Table,  TableBody,  TableCell,  TableContainer,  TableHead,  TableRow,  Paper,  Box,  CircularProgress,  Alert } from '@mui/material';

// ฟังก์ชันสำหรับจัดรูปแบบตัวเลข (ไม่มีการเปลี่ยนแปลง)
const formatNumber = (num) => {
  if (num === null || num === undefined || num ===0 ) return ''; // แสดงเป็น '0' แทนค่าว่าง
  return new Intl.NumberFormat('en-US').format(num);
};

// ย้ายค่าคงที่ออกนอกคอมโพเนนต์เพื่อประสิทธิภาพที่ดีขึ้น
const TABLE_HEADERS = ['รูปแบบการส่ง', 'ลังเล็ก', 'ลังใหญ่','FullCase', ' สื่อ ',  'Grand Total'];

export default function DeliveryStatsPage() {
  const [data, setData] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    const fetchData = async () => {
      try {
        setLoading(true);
        setError(null);
        // สมมติว่านี่คือ API endpoint ของคุณ
        const response = await fetch('/api/delivery-stats');

        if (!response.ok) {
          throw new Error(`เกิดข้อผิดพลาดจากเซิร์ฟเวอร์: ${response.status}`);
        }

        const result = await response.json();
        // ตรวจสอบให้แน่ใจว่าผลลัพธ์ที่ได้เป็น array
        if (Array.isArray(result)) {
          setData(result);
        } else {
          throw new Error("ข้อมูลที่ได้รับจาก API ไม่ใช่รูปแบบที่ถูกต้อง");
        }

      } catch (e) {
        console.error("Failed to fetch data:", e);
        setError(e.message || "ไม่สามารถดึงข้อมูลได้ กรุณาตรวจสอบการเชื่อมต่อหรือ API");
      } finally {
        setLoading(false);
      }
    };

    fetchData();
  }, []); // <-- [IMPROVEMENT] ระบุ dependency array ว่างเปล่าเพื่อให้ effect นี้ทำงานครั้งเดียว

  // ใช้ useMemo เพื่อคำนวณค่าสรุปรวมทั้งหมด (Grand Total)
  // จะคำนวณใหม่ก็ต่อเมื่อ 'data' มีการเปลี่ยนแปลงเท่านั้น
  const grandTotal = useMemo(() => {
    // ตรวจสอบให้แน่ใจว่า `data` เป็น array ก่อนใช้ reduce
    if (!Array.isArray(data)) {
        return { smallBox: 0, largeBox: 0, outsideBox: 0, fullBox: 0, total: 0 };
    }
    const totals = data.reduce(
      (acc, row) => {
        acc.smallBox += row.smallBox || 0;
        acc.largeBox += row.largeBox || 0;
        acc.outsideBox += row.outsideBox || 0;
        acc.fullBox += row.fullBox || 0;
        return acc;
      },
      { smallBox: 0, largeBox: 0, outsideBox: 0, fullBox: 0 }
    );
    totals.total = totals.smallBox + totals.largeBox + totals.outsideBox + totals.fullBox;
    return totals;
  }, [data]);

  // ใช้ useMemo เพื่อสร้าง JSX ของแถวในตาราง
  // ช่วยให้ไม่ต้องสร้าง element ใหม่ทุกครั้งที่ re-render ถ้า 'data' ไม่เปลี่ยน
  const tableRows = useMemo(() => {
    // ตรวจสอบให้แน่ใจว่า `data` เป็น array ก่อนใช้ map
    if (!Array.isArray(data)) return null;

    return data.map((row) => {
      const rowTotal = (row.smallBox || 0) + (row.largeBox || 0) + (row.outsideBox || 0) + (row.fullBox || 0);
      return (
        <TableRow
          key={row.location} // ใช้ key ที่มีเอกลักษณ์สำหรับแต่ละแถว
          sx={{
            '&:nth-of-type(odd)': { backgroundColor: 'action.hover' },
            '&:hover': { backgroundColor: 'primary.lighter' }
          }}
        >
          <TableCell component="th" scope="row" sx={{ fontWeight: '500' }}>
            {row.location}
          </TableCell>
          <TableCell align="right">{formatNumber(row.smallBox)}</TableCell>
          <TableCell align="right">{formatNumber(row.largeBox)}</TableCell>
          <TableCell align="right">{formatNumber(row.fullBox)}</TableCell>
          <TableCell align="right">{formatNumber(row.outsideBox)}</TableCell>          
          <TableCell align="right" sx={{ fontWeight: 'bold', color: 'primary.dark' }}>
            {formatNumber(rowTotal)}
          </TableCell>
        </TableRow>
      );
    });
  }, [data]);

  const renderContent = () => {
    if (loading) {
      return (
        <Box sx={{ display: 'flex', justifyContent: 'center', mt: 4 }}>
          <CircularProgress />
        </Box>
      );
    }

    if (error) {
      return (
        <Alert severity="error" sx={{ mt: 2 }}>
          {error}
        </Alert>
      );
    }

    return (
      <TableContainer component={Paper} elevation={3}>
        <Table aria-label="delivery statistics table">
          <TableHead>
            <TableRow>
              {TABLE_HEADERS.map((header) => (
                <TableCell
                  key={header}
                  align={header !== 'รูปแบบการส่ง' ? 'right' : 'left'}
                  sx={{
                    backgroundColor: 'primary.dark',
                    color: 'common.white',
                    fontWeight: 'bold',
                    fontSize: '1rem',
                  }}
                >
                  {header}
                </TableCell>
              ))}
            </TableRow>
          </TableHead>
          <TableBody>
            {tableRows}
            {/* แถวสรุป Grand Total */}
            <TableRow sx={{
              backgroundColor: 'primary.dark',
              '& > *': {
                fontWeight: 'bold !important',
                // color: 'common.white !important',
                color: 'common.white',
                fontSize: '1.1rem'
              }
            }}>
              <TableCell>Grand Total</TableCell>
              <TableCell align="right">{formatNumber(grandTotal.smallBox)}</TableCell>
              <TableCell align="right">{formatNumber(grandTotal.largeBox)}</TableCell>
              <TableCell align="right">{formatNumber(grandTotal.fullBox)}</TableCell>
              <TableCell align="right">{formatNumber(grandTotal.outsideBox)}</TableCell>
              <TableCell align="right">{formatNumber(grandTotal.total)}</TableCell>
            </TableRow>
          </TableBody>
        </Table>
      </TableContainer>
    );
  };

  return (
    <Container maxWidth="lg" sx={{ mt: 4, mb: 4 }}>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
        <Typography variant="h4" component="h1" sx={{ fontWeight: 'bold' }}>
          รายงานสรุปยอดจัดส่ง
        </Typography>
      </Box>
      {renderContent()}
    </Container>
  );
}