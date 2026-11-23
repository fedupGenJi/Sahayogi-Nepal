import React from 'react';
import ReactDOM from 'react-dom/client';
import SetPasswordPage from './pages/SetPasswordPage';
import './styles/admin.css';
import './styles/login.css';

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <SetPasswordPage />
  </React.StrictMode>,
);
