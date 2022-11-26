// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using System;
using System.Collections.Generic;
using System.Net;
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
using AWS.Lambda.Powertools.Tracing;
using AWS.Lambda.Powertools.Metrics;
using DynamoDBContextConfig = Amazon.DynamoDBv2.DataModel.DynamoDBContextConfig;

// Assembly attribute to enable the Lambda function's JSON input to be converted into a .NET class.
[assembly: LambdaSerializer(typeof(Amazon.Lambda.Serialization.SystemTextJson.DefaultLambdaJsonSerializer))]

namespace Unicorn.Contracts.ContractService;

public class CreateContractFunction
{
    private readonly IDynamoDBContext _dynamoDbContext;
    private readonly IPublisher _publisher;

    /// <summary>
    /// Default constructor for CreateContractFunction
    /// </summary>
    public CreateContractFunction()
    {
        // Instrument all AWS SDK calls
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
    /// Testing constructor for CreateContractFunction
    /// </summary>
    /// <param name="dynamoDbContext"></param>
    /// <param name="publisher"></param>
    public CreateContractFunction(IDynamoDBContext dynamoDbContext, IPublisher publisher)
    {
        _publisher = publisher;
        _dynamoDbContext = dynamoDbContext;
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
        CreateContractRequest contractRequest;
        try
        {
            contractRequest = ValidateRequestBody(apigProxyEvent);
        }
        catch (EventValidationException e)
        {
            Logger.LogError(e.Message);
            throw;
        }

        // check to see if we already have a contract with the same ID
        var existingContract = await TryGetContractById(contractRequest.PropertyId ?? "").ConfigureAwait(false);
        if (existingContract != null)
        {
            return new APIGatewayProxyResponse
            {
                Body = JsonSerializer.Serialize(existingContract),
                StatusCode = (int)HttpStatusCode.OK,
                Headers = new Dictionary<string, string> { { "Content-Type", "application/json" } }
            };
        }

        // new contract 
        var contract = new Contract
        {
            PropertyId = contractRequest.PropertyId,
            ContractId = Guid.NewGuid(),
            Address = contractRequest.Address,
            SellerName = contractRequest.SellerName
        };
        
        Logger.AppendKey("Contract", contract);
        Logger.LogInformation("Creating new contract");

        // Create entry in DDB for new contract
        await CreateContract(contract).ConfigureAwait(false);
        
        // Publish ContractStatusChanged event
        await _publisher.PublishEvent(contract).ConfigureAwait(false);
        
        // return generated contract ID back to user:
        return new APIGatewayProxyResponse
        {
            Body = JsonSerializer.Serialize(contract),
            StatusCode = (int)HttpStatusCode.OK,
            Headers = new Dictionary<string, string> { { "Content-Type", "application/json" } }
        };
    }

    /// <summary>
    /// Parse data to create a new contract.
    /// </summary>
    /// <param name="apigProxyEvent">The API Gateway Proxy Request</param>
    /// <returns>Instance of <see cref="CreateContractRequest"/>, the strongly-typed representation of the API Gateway body</returns>
    private CreateContractRequest ValidateRequestBody(APIGatewayProxyRequest apigProxyEvent)
    {
        Logger.LogInformation("Parsing API Gateway request body to CreateContractRequest type.");
        
        CreateContractRequest? request; 
        
        try 
        {
            if (apigProxyEvent.Body == null)
                throw new EventValidationException("API Gateway.");
            
            request = JsonSerializer.Deserialize<CreateContractRequest>(apigProxyEvent.Body, new JsonSerializerOptions()
            {
                PropertyNameCaseInsensitive = true
            });
        }
        catch (Exception e)
        {
            throw new EventValidationException("Unable to convert APIGatewayProxyRequest to CreateContractRequest.", e);
        }

        if (request == null)
            throw new EventValidationException("Unable to convert APIGatewayProxyRequest to CreateContractRequest.");

        if (string.IsNullOrEmpty(request.PropertyId))
            throw new EventValidationException("Request does not contain a Property ID.");

        return request;
    }

    /// <summary>
    /// Queries database for existing contract
    /// </summary>
    /// <param name="propertyId">Property ID</param>
    /// <returns>Instance of <see cref="Contract"/></returns>
    [Tracing(SegmentName = "Existing contract")]
    private async Task<Contract?> TryGetContractById(string propertyId)
    {
        try
        {
            Logger.LogInformation($"Contract for Property ID: `{propertyId}` already exists");
            var contract = await _dynamoDbContext.LoadAsync<Contract>(propertyId);
            Logger.LogInformation($"Contract for Property ID: `{propertyId}` already exists");
            return contract;
        }
        catch (Exception e)
        {
            Logger.LogInformation($"Error loading contract {propertyId}: {e.Message}");
        }

        return null;
    }


    /// <summary>
    /// 
    /// </summary>
    /// <param name="contract"></param>
    /// <returns></returns>
    [Tracing(SegmentName = "Create Contract")]
    private async Task CreateContract(Contract contract)
    {
        try
        {
            Logger.LogInformation($"Saving contract for Property ID: {contract.PropertyId}");
            await _dynamoDbContext.SaveAsync(contract);
        }
        catch (Exception e)
        {
            Logger.LogError(e.Message);
            throw;
        }
    }
}