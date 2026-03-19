import React from 'react';
import { Button } from 'primereact/button';

interface SaveCancelDialogFooterProps {
  onCancel: () => void;
  onSave: () => void;
  cancelLabel: string;
  saveLabel: string;
  cancelIcon: string;
  saveIcon: string;
}

const SaveCancelDialogFooter: React.FC<SaveCancelDialogFooterProps> = ({
  onCancel,
  onSave,
  cancelLabel,
  saveLabel,
  cancelIcon,
  saveIcon,
}) => {
  return (
    <>
      <Button label={cancelLabel} icon={cancelIcon} text onClick={onCancel} />
      <Button label={saveLabel} icon={saveIcon} text onClick={onSave} />
    </>
  );
};

export default SaveCancelDialogFooter;
