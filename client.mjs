import { SecretsManagerClient, PutSecretValueCommand, DeleteSecretCommand } from "@aws-sdk/client-secrets-manager";
import { SSMClient, PutParameterCommand, DeleteParameterCommand } from "@aws-sdk/client-ssm";

export class Client {
  constructor(useSecretsManager) {
    this.client = useSecretsManager ? new SecretsManagerClient({}) : new SSMClient({});
    this.useSecretsManager = useSecretsManager;
  }

  async create(name, value) {
    const ssmCommand = new PutParameterCommand({
      Name: name,
      Value: value,
      Type: 'SecureString',
    });
    const secretsManagerCommand = new PutSecretValueCommand({
      SecretId: name,
      SecretString: value
    });
    const command = this.useSecretsManager ? secretsManagerCommand : ssmCommand;
    try {
      const response = await this.client.send(command);
      console.log("Secret created:", response);
      return response;
    } catch (error) {
      console.error("Error creating secret:", error);
      throw error;
    }
  }

  async delete(name) {
    const ssmCommand = new DeleteParameterCommand({Name: name});
    const secretsManagerCommand = new DeleteSecretCommand({SecretId: name});
    const command = this.useSecretsManager ? secretsManagerCommand : ssmCommand;
    try {
      const response = await this.client.send(command);
      console.log("Secret deleted:", response);
      return response;
    } catch (error) {
      console.error("Error deleting secret:", error);
      throw error;
    }
  }
}
