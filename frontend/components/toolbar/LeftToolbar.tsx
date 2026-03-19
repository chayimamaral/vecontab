import React from 'react';
import { Button } from 'primereact/button';

interface LeftToolbarProps {
  label: string;
  icon: string;
  severity: string;
  onClick: () => void;
  // Add more props if needed for delete functionality or other features
}

const LeftToolbar: React.FC<LeftToolbarProps> = ({ label, icon, severity, onClick }) => {
  return (
    <div className="my-2">
      <Button label={label} icon="pi pi-plus" severity="success" className="mr-2" onClick={onClick} />
      {/* You can add the delete button or any other functionality here */}
    </div>
  );
};

export default LeftToolbar;
