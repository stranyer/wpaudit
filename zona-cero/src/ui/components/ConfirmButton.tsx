import { useEffect, useState, type ReactNode } from 'react';

/**
 * Botón con confirmación en dos toques (sin `window.confirm`, que algunas vistas web
 * bloquean). El primer toque arma la acción por 3 s; el segundo la ejecuta.
 */
export function ConfirmButton({
  onConfirm,
  children,
  confirmLabel = '¿Seguro? Tocá de nuevo',
  className = 'btn',
}: {
  onConfirm: () => void;
  children: ReactNode;
  confirmLabel?: string;
  className?: string;
}) {
  const [armed, setArmed] = useState(false);
  useEffect(() => {
    if (!armed) return;
    const t = setTimeout(() => setArmed(false), 3000);
    return () => clearTimeout(t);
  }, [armed]);
  return (
    <button
      className={className}
      onClick={() => {
        if (!armed) return setArmed(true);
        setArmed(false);
        onConfirm();
      }}
    >
      {armed ? confirmLabel : children}
    </button>
  );
}
