import {generate, cleanup} from "./code.mjs";
import {Client} from "./client.mjs"

export const handler = async (event) => {
	const parameterName = process.env.PARAMETER_NAME;
  const useSecretsManager = ['true', '1'].includes(process.env.USE_SECRETS_MANAGER)
	const client = new Client(useSecretsManager);
	if (event.tf.action === "delete") {
		await client.delete(parameterName);
		await cleanup();
	}
	if (event.tf.action === "create") {
		const {value, outputs} = await generate();
		await client.create(parameterName, value);
		return outputs;
	}
}
