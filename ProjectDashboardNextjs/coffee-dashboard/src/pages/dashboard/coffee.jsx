import { useState, useEffect } from 'react';
import Head from 'next/head';
import {
    Container, Typography, Grid, Card, CardContent, CardMedia,
    TextField, Button, Box, CircularProgress, Alert
} from '@mui/material';
import AddCircleOutlineIcon from '@mui/icons-material/AddCircleOutline';

// Component สำหรับแสดง Card กาแฟแต่ละใบ
const CoffeeCard = ({ coffee }) => (
    <Card sx={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
        <CardMedia
            component="img"
            height="180"
            image={coffee.ImageUrl || 'https://via.placeholder.com/300x180.png?text=Coffee'}
            alt={coffee.Name}
        />
        <CardContent sx={{ flexGrow: 1 }}>
            <Typography gutterBottom variant="h5" component="div">
                {coffee.Name}
            </Typography>
            <Typography variant="body2" color="text.secondary">
                Origin: {coffee.Origin}
            </Typography>
            <Typography variant="h6" color="primary" sx={{ mt: 2 }}>
                ${parseFloat(coffee.Price).toFixed(2)}
            </Typography>
        </CardContent>
    </Card>
);

// Component ฟอร์มสำหรับเพิ่มกาแฟ
const AddCoffeeForm = ({ onAddCoffee }) => {
    const [name, setName] = useState('');
    const [origin, setOrigin] = useState('');
    const [price, setPrice] = useState('');

    const handleSubmit = (e) => {
        e.preventDefault();
        if (!name || !origin || !price) {
            alert('Please fill all fields');
            return;
        }
        onAddCoffee({ name, origin, price: parseFloat(price) });
        // Reset form
        setName('');
        setOrigin('');
        setPrice('');
    };

    return (
        <Card sx={{ p: 3, mb: 4 }}>
            <Typography variant="h5" gutterBottom>Add New Coffee</Typography>
            <Box component="form" onSubmit={handleSubmit} noValidate sx={{ mt: 1 }}>
                <Grid container spacing={2}>
                    <Grid item xs={12} sm={6}>
                        <TextField
                            fullWidth
                            label="Coffee Name"
                            value={name}
                            onChange={(e) => setName(e.target.value)}
                            required
                        />
                    </Grid>
                    <Grid item xs={12} sm={6}>
                        <TextField
                            fullWidth
                            label="Origin"
                            value={origin}
                            onChange={(e) => setOrigin(e.target.value)}
                            required
                        />
                    </Grid>
                    <Grid item xs={12}>
                        <TextField
                            fullWidth
                            label="Price"
                            type="number"
                            value={price}
                            onChange={(e) => setPrice(e.target.value)}
                            required
                        />
                    </Grid>
                </Grid>
                <Button
                    type="submit"
                    variant="contained"
                    startIcon={<AddCircleOutlineIcon />}
                    sx={{ mt: 3 }}
                >
                    Add Coffee
                </Button>
            </Box>
        </Card>
    );
};


export default function CoffeeDashboard() {
    const [coffees, setCoffees] = useState([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);

    // ฟังก์ชันสำหรับดึงข้อมูลกาแฟ
    const fetchCoffees = async () => {
        setLoading(true);
        setError(null);
        try {
            // ใช้ Fetch API ตามที่คุณต้องการ
            const response = await fetch('/api/coffees');
            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
            const data = await response.json();
            setCoffees(data);
        } catch (e) {
            console.error("Failed to fetch coffees:", e);
            setError('Could not load coffee data. Please try again later.');
        } finally {
            setLoading(false);
        }
    };

    // ดึงข้อมูลเมื่อ Component โหลดครั้งแรก
    useEffect(() => {
        fetchCoffees();
    }, []);

    // ฟังก์ชันสำหรับจัดการการเพิ่มกาแฟ
    const handleAddCoffee = async (newCoffee) => {
        try {
            const response = await fetch('/api/coffees', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(newCoffee),
            });
            if (!response.ok) {
                throw new Error('Failed to add coffee');
            }
            // ดึงข้อมูลใหม่เพื่ออัปเดต UI
            fetchCoffees();
        } catch (e) {
            console.error("Failed to add coffee:", e);
            setError('Could not add coffee. Please try again.');
        }
    };

    return (
        <>
            <Head>
                <title>Coffee Dashboard</title>
                <meta name="description" content="Manage your coffee inventory" />
            </Head>
            <Container maxWidth="lg" sx={{ py: 4 }}>
                <Typography variant="h4" component="h1" gutterBottom>
                    Coffee Inventory Dashboard
                </Typography>

                <AddCoffeeForm onAddCoffee={handleAddCoffee} />

                {error && <Alert severity="error" sx={{ mb: 2 }}>{error}</Alert>}

                {loading ? (
                    <Box sx={{ display: 'flex', justifyContent: 'center', my: 4 }}>
                        <CircularProgress />
                    </Box>
                ) : (
                    <Grid container spacing={4}>
                        {coffees.map((coffee) => (
                            <Grid item key={coffee.Id} xs={12} sm={6} md={4}>
                                <CoffeeCard coffee={coffee} />
                            </Grid>
                        ))}
                    </Grid>
                )}
            </Container>
        </>
    );
}