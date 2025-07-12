import { useState, useEffect } from 'react';
import {
  Container,
  Typography,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Paper,
  Box,
  CircularProgress,
  Alert
} from '@mui/material';

// ฟังก์ชันสำหรับจัดรูปแบบตัวเลข
const formatNumber = (num) => {
  if (num === null || num === undefined) return '';
  return new Intl.NumberFormat('en-US').format(num);
};

export default function DeliveryStatsPage() {
  const [data, setData] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    const fetchData = async () => {
      try {
        setLoading(true);
        setError(null);
        const response = await fetch('/api/delivery-stats');
        
        if (!response.ok) {
          throw new Error(`HTTP error! status: ${response.status}`);
        }
        
        const result = await response.json();
        setData(result);
      } catch (e) {
        console.error("Failed to fetch data:", e);
        setError("ไม่สามารถดึงข้อมูลจากฐานข้อมูลได้ กรุณาตรวจสอบ API หรือการเชื่อมต่อ");
      } finally {
        setLoading(false);
      }
    };

    fetchData();
  }, []);

  const grandTotal = data.reduce(
    (acc, row) => {
      acc.smallBox += row.smallBox || 0;
      acc.largeBox += row.largeBox || 0;
      acc.outsideBox += row.outsideBox || 0;
      return acc;
    },
    { smallBox: 0, largeBox: 0, outsideBox: 0 }
  );
  grandTotal.total = grandTotal.smallBox + grandTotal.largeBox + grandTotal.outsideBox;

  const tableHeaders = ['รูปแบบการส่ง', 'ลังเล็ก', 'ลังใหญ่', 'สินค้านอกลัง', 'Grand Total'];

  return (
    <Container maxWidth="lg" sx={{ mt: 4, mb: 4 }}>
      <Typography variant="h4" component="h1" gutterBottom>
        รายงานสถิติการจัดส่ง
      </Typography>
      
      {loading && (
        <Box sx={{ display: 'flex', justifyContent: 'center', mt: 4 }}>
          <CircularProgress />
        </Box>
      )}

      {error && (
        <Alert severity="error" sx={{ mt: 2 }}>{error}</Alert>
      )}

      {!loading && !error && (
        <TableContainer component={Paper}>
          <Table aria-label="delivery statistics table">
            <TableHead>
              <TableRow sx={{ backgroundColor: '#1976d2' }}>
                {tableHeaders.map((header) => (
                  <TableCell
                    key={header}
                    align={header !== 'รูปแบบการส่ง' ? 'right' : 'left'}
                    sx={{ color: 'white', fontWeight: 'bold' }}
                  >
                    {header}
                  </TableCell>
                ))}
              </TableRow>
            </TableHead>
            <TableBody>
              {data.map((row, index) => {
                const rowTotal = (row.smallBox || 0) + (row.largeBox || 0) + (row.outsideBox || 0);
                return (
                  <TableRow key={row.id || index} sx={{ '&:last-child td, &:last-child th': { border: 0 } }}>
                    <TableCell component="th" scope="row">{row.location}</TableCell>
                    <TableCell align="right">{formatNumber(row.smallBox)}</TableCell>
                    <TableCell align="right">{formatNumber(row.largeBox)}</TableCell>
                    <TableCell align="right">{formatNumber(row.outsideBox)}</TableCell>
                    <TableCell align="right" sx={{ fontWeight: 'medium' }}>{formatNumber(rowTotal)}</TableCell>
                  </TableRow>
                );
              })}
              <TableRow sx={{ backgroundColor: '#f5f5f5', '& > *': { fontWeight: 'bold !important' } }}>
                <TableCell>Grand Total</TableCell>
                <TableCell align="right">{formatNumber(grandTotal.smallBox)}</TableCell>
                <TableCell align="right">{formatNumber(grandTotal.largeBox)}</TableCell>
                <TableCell align="right">{formatNumber(grandTotal.outsideBox)}</TableCell>
                <TableCell align="right">{formatNumber(grandTotal.total)}</TableCell>
              </TableRow>
            </TableBody>
          </Table>
        </TableContainer>
      )}
    </Container>
  );
}