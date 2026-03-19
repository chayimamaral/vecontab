import { Button } from 'primereact/button';
import React from 'react';


function PaginatorLeft({ onClick }) {
  return (
    <Button
      type="button"
      icon="pi pi-refresh"
      tooltip="Atualizar"
      className="p-button-text"
      onClick={onClick}
    />
  );
}

export default PaginatorLeft;
