import { canSSRAuth } from "../components/utils/canSSRAuth"

export default function Home(){
    return(
        <h1>Bem vindo ao VECONTAB</h1>
    )
}

export const getServerSideProps = canSSRAuth(async (ctx) => {

    return {
      props: {
  
      }
    }
  })