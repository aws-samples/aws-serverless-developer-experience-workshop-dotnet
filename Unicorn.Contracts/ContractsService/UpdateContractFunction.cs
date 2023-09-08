// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Threading.Tasks;
using Amazon;
using Amazon.DynamoDBv2;
using Amazon.DynamoDBv2.DataModel;
using Amazon.Lambda.APIGatewayEvents;
using Amazon.Lambda.Core;
using Amazon.Util;
using Amazon.XRay.Recorder.Handlers.AwsSdk;
using AWS.Lambda.Powertools.Logging;
using AWS.Lambda.Powertools.Metrics;
using AWS.Lambda.Powertools.Tracing;
using DynamoDBContextConfig = Amazon.DynamoDBv2.DataModel.DynamoDBContextConfig;

namespace Unicorn.Contracts.ContractService
{
    public class UpdateContractFunction
    {
        private readonly IDynamoDBContext _dynamoDbContext;
        private readonly IPublisher _publisher;

        /// <summary>
        /// Default constructor for CreateContractFunction
        /// </summary>
        public UpdateContractFunction()
        {
            AWSSDKHandler.RegisterXRayForAllServices();

            _publisher = new Publisher();
            
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
        /// Testing constructor for UpdateContractFunction
        /// </summary>
        /// <param name="dynamoDbContext">Instance of IDynamoDbContext</param>
        /// <param name="publisher">Instance of IPublisher</param>
        public UpdateContractFunction(IDynamoDBContext dynamoDbContext, IPublisher publisher)
        {
            _dynamoDbContext = dynamoDbContext;
            _publisher = publisher;
        }

        /// <summary>
        /// Lambda Handler for creating new Contracts.
        /// </summary>
        /// <param name="apigProxyEvent">API Gateway Lambda Proxy Request that triggers the function.</param>
        /// <param name="context">The context for the Lambda function.</param>
        /// <returns>API Gateway Lambda Proxy Response.</returns>
        [Logging(LogEvent = true)]
        [Metrics(CaptureColdStart = true)]
        [Tracing(CaptureMode = TracingCaptureMode.ResponseAndError)]
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
            await _publisher.PublishEvent(existingContract).ConfigureAwait(false);

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
                Logger.LogInformation($"Getting contract {propertyId}");
                var contract = await _dynamoDbContext.LoadAsync<Contract>(propertyId).ConfigureAwait(false);
                Logger.LogInformation($"Found contact: {contract != null}");
                return contract;
            }
            catch (Exception e)
            {
                Logger.LogError($"Error loading contract {propertyId}: {e.Message}");
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
                Logger.LogInformation($"Saving contract with id {contract.PropertyId}");
                await _dynamoDbContext.SaveAsync(contract).ConfigureAwait(false);
            }
            catch (AmazonDynamoDBException e)
            {
                Logger.LogError(e);
                throw;
            }
        }
    }
}