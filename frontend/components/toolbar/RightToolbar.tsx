import React from 'react';
import { Button } from 'primereact/button';

interface RightToolbarProps {
  onExportCSV: () => void;
  // Add more props if needed for delete functionality or other features
}

const RightToolbar: React.FC<RightToolbarProps> = ({ onExportCSV }) => {
  return (
    <div className="my-2">
      <Button label="Exportar" icon="pi pi-upload" severity="help" onClick={onExportCSV} />
      {/* You can add the delete button or any other functionality here */}
    </div>
  );
};

export default RightToolbar;
