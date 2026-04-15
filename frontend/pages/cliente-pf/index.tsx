import setupAPIClient from '../../components/api/api';
import { canSSRAuth } from '../../components/utils/canSSRAuth';
import { EmpresasPage } from '../empresas';

export default function ClientePF({ dados }: { dados: string }) {
  return <EmpresasPage dados={dados} tipoPessoa="PF" />;
}

export const getServerSideProps = canSSRAuth(async (ctx) => {
  try {
    const apiClient = setupAPIClient(ctx);
    const response = await apiClient.get('/api/usuariotenant');

    return {
      props: {
        dados: response.data.tenantid,
      },
    };
  } catch (err) {
    console.log(err);

    return {
      redirect: {
        destination: '/',
        permanent: false,
      },
    };
  }
});
