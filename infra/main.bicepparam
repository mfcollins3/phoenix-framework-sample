using './main.bicep'

param environmentName = readEnvironmentVariable('AZURE_ENV_NAME', 'sample')
param location = readEnvironmentVariable('AZURE_LOCATION', 'centralus')
