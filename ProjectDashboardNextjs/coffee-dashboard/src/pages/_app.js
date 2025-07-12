// src/pages/_app.js
import { ThemeProvider } from '@mui/material/styles';
import CssBaseline from '@mui/material/CssBaseline';
import theme from '@/styles/theme';
import '@/styles/globals.css'; // หากยังต้องการใช้

export default function App({ Component, pageProps }) {
  return (
    <ThemeProvider theme={theme}>
      {/* CssBaseline คือตัวช่วย reset CSS ให้ทำงานกับ MUI ได้ดี */}
      <CssBaseline />
      <Component {...pageProps} />
    </ThemeProvider>
  );
}