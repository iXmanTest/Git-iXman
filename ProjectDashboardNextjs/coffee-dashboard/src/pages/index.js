// src/pages/index.js
import { useEffect } from 'react';
import { useRouter } from 'next/router';

export default function HomePage() {
  const router = useRouter();

  useEffect(() => {
    router.replace('/dashboard/coffee');
  }, [router]);

  return (
    <div>Redirecting...</div>
  );
}