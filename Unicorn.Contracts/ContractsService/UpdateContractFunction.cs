// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Threading.Tasks;
using Amazon;
using Amazon.DynamoDBv2;
using Amazon.DynamoDBv2.DataModel;
using Amazon.EventBridge;
using Amazon.Lambda.APIGatewayEvents;
using Amazon.Lambda.Core;
using Amazon.Util;
using AWS.Lambda.Powertools.Logging;
using AWS.Lambda.Powertools.Metrics;
using AWS.Lambda.Powertools.Tracing;
using DynamoDBContextConfig = Amazon.DynamoDBv2.DataModel.DynamoDBContextConfig;

// Assembly attribute to enable the Lambda function's JSON input to be converted into a .NET class.
// [assembly: LambdaSerializer(typeof(Amazon.Lambda.Serialization.SystemTextJson.DefaultLambdaJsonSerializer))]

namespace Unicorn.Contracts.ContractService
{
    public class UpdateContractFunction
    {
        private readonly IDynamoDBContext _dynamoDbContext;

        /// <summary>
        /// Default constructor for CreateContractFunction
        /// </summary>
        public UpdateContractFunction()
        {
            var dynamodbTable = Environment.GetEnvironmentVariable("DYNAMODB_TABLE");
            if (string.IsNullOrEmpty(dynamodbTable))
            {
                throw new Exception("Environment variable DYNAMODB_TABLE is not defined.");
            }

            AWSConfigsDynamoDB.Context.TypeMappings[typeof(Contract)] =
                new TypeMapping(typeof(Contract), dynamodbTable);

            var config = new DynamoDBContextConfig { Conversion = DynamoDBEntryConversion.V2 };
            _dynamoDbContext = new DynamoDBContext(new AmazonDynamoDBClient(), config);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="dynamoDbContext"></param>
        /// <param name="eventBridgeClient"></param>
        /// <param name="serviceNamespace"></param>
        public UpdateContractFunction(IDynamoDBContext dynamoDbContext, AmazonEventBridgeClient eventBridgeClient,
            string serviceNamespace)
        {
            _dynamoDbContext = dynamoDbContext;
        }

        /// <summary>
        /// Lambda Handler for creating new Contracts.
        /// </summary>
        /// <param name="apigProxyEvent">API Gateway Lambda Proxy Request that triggers the function.</param>
        /// <param name="context">The context for the Lambda function.</param>
        /// <returns>API Gateway Lambda Proxy Response.</returns>
        [Tracing]
        [Metrics(CaptureColdStart = true)]
        [Logging(LogEvent = true, CorrelationIdPath = CorrelationIdPaths.ApiGatewayRest)]
        public async Task<APIGatewayProxyResponse> FunctionHandler(APIGatewayProxyRequest apigProxyEvent,
            ILambdaContext context)
        {
            // Validate request body
            var contractUpdateRequest = ValidateEvent(apigProxyEvent);

            // check to see if contract exists
            var existingContract = await GetExistingContract(contractUpdateRequest.PropertyId).ConfigureAwait(false);
            if(existingContract == null)
                throw new ContractNotFoundException($"Could not find property with ID: {contractUpdateRequest.PropertyId}");
            
            // Update status
            existingContract.ContractLastModifiedOn = DateTime.Now;
            existingContract.ContractStatus = ContractStatus.Approved;

            // Create entry in DDB for new contract
            await UpdateContract(existingContract).ConfigureAwait(false);

            // Publish ContractStatusChanged event
            var publisher = new Publisher();
            await publisher.PublishEvent(existingContract);

            // return generated contract ID back to user:
            return new APIGatewayProxyResponse
            {
                Body = JsonSerializer.Serialize(existingContract),
                StatusCode = 200,
                Headers = new Dictionary<string, string> { { "Content-Type", "application/json" } }
            };
        }

        /// <summary>
        /// Parse Contract defined in the APIGatewayProxyRequest body.
        /// </summary>
        /// <param name="apigProxyEvent"></param>
        /// <returns></returns>
        private UpdateContractRequest ValidateEvent(APIGatewayProxyRequest apigProxyEvent)
        {
            var options = new JsonSerializerOptions()
            {
                PropertyNameCaseInsensitive = true
            };

            try
            {
                var contract = JsonSerializer.Deserialize<UpdateContractRequest>(apigProxyEvent.Body, options);

                if (contract == null || string.IsNullOrEmpty(contract.PropertyId))
                    throw new EventValidationException("Unable to convert APIGatewayProxyRequest to Contract.");

                return contract;
            }
            catch (Exception exception)
            {
                Console.WriteLine(exception);
                throw new EventValidationException("Unable to convert APIGatewayProxyRequest to Contract.");
            }
        }

        /// <summary>
        /// Returns Contract for a specified property.
        /// </summary>
        /// <param name="propertyId">Property ID</param>
        /// <returns>Instance of <see cref="Contract">Contract</see></returns>
        /// <exception cref="ContractNotFoundException"></exception>
        private async Task<Contract?> GetExistingContract(string? propertyId)
        {
            try
            {
                Console.WriteLine($"Getting contract {propertyId}");
                var contract = await _dynamoDbContext.LoadAsync<Contract>(propertyId).ConfigureAwait(false);
                Console.WriteLine($"Found contact: {contract != null}");
                return contract;
            }
            catch (Exception e)
            {
                Console.WriteLine($"Error loading contract {propertyId}: {e.Message}");
                return null;
            }
        }


        /// <summary>
        /// 
        /// </summary>
        /// <param name="contract"></param>
        /// <returns></returns>
        private async Task UpdateContract(Contract contract)
        {
            try
            {
                Console.WriteLine($"Saving contract with id {contract.PropertyId}");
                await _dynamoDbContext.SaveAsync(contract).ConfigureAwait(false);
            }
            catch (AmazonDynamoDBException e)
            {
                Console.WriteLine(e);
                throw;
            }
        }
    }
}