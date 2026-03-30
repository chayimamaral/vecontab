import { useEffect } from 'react';
import { useRouter } from 'next/router';
import { GetServerSidePropsContext } from 'next';
import { withAuthServerSideProps } from '../../components/utils/crudUtils';

/** Rota antiga; o cadastro unificado está em `/obrigacoes`. */
const CompromissosRedirect = () => {
  const router = useRouter();

  useEffect(() => {
    void router.replace('/obrigacoes');
  }, [router]);

  return null;
};

export default CompromissosRedirect;

export const getServerSideProps = withAuthServerSideProps(async (_ctx: GetServerSidePropsContext) => {
  // sem processamento adicional
});
