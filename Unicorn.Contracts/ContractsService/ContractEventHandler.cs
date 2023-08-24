// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using System;
using System.Threading.Tasks;
using Amazon;
using Amazon.DynamoDBv2;
using Amazon.DynamoDBv2.DataModel;
using Amazon.Lambda.Core;
using Amazon.Lambda.SQSEvents;
using Amazon.Util;
using Amazon.XRay.Recorder.Handlers.AwsSdk;
using AWS.Lambda.Powertools.Logging;
using AWS.Lambda.Powertools.Metrics;
using AWS.Lambda.Powertools.Tracing;
using DynamoDBContextConfig = Amazon.DynamoDBv2.DataModel.DynamoDBContextConfig;

namespace Unicorn.Contracts.ContractService;

/// <summary>
/// 
/// </summary>
public class ContractEventHandler
{
    private readonly IDynamoDBContext _dynamoDbContext;

    /// <summary>
    /// Default constructor for ContractEventHandler
    /// </summary>
    public ContractEventHandler()
    {
        // Instrument all AWS SDK calls
        AWSSDKHandler.RegisterXRayForAllServices();
        
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
    /// Testing constructor for ContractEventHandler
    /// </summary>
    /// <param name="dynamoDbContext"></param>
    /// <param name="publisher"></param>
    public ContractEventHandler(IDynamoDBContext dynamoDbContext, IPublisher publisher)
    {
        _dynamoDbContext = dynamoDbContext;
    }


    /// <summary>
    /// Lambda Handler for creating new Contracts.
    /// </summary>
    /// <param name="sqsEvent">AWS SQS record. Could contain batch of records.</param>
    /// <param name="context">The context for the Lambda function.</param>
    /// <returns>API Gateway Lambda Proxy Response.</returns>
    [Logging(LogEvent = true)]
    [Metrics(CaptureColdStart = true)]
    [Tracing(CaptureMode = TracingCaptureMode.ResponseAndError)]
    public Task<string> FunctionHandler(SQSEvent sqsEvent, ILambdaContext context)
    {
        Logger.LogInformation($"Beginning to process {sqsEvent.Records.Count} records...");

        foreach (var record in sqsEvent.Records)
        {
            // if record.MessageAttributes["HttpMethod"] == "POST"
            // {
                
            // }
            
            // if POST 
            CreateContract(record);
            // If PUT 
            // UpdateContract()

            Logger.LogInformation($"Message ID: {record.MessageId}");
            Logger.LogInformation($"Event Source: {record.EventSource}");

            Logger.LogInformation($"Record Body:");
            Logger.LogInformation(record.Body);
            Logger.LogInformation($"Method: {record.MessageAttributes[""]}");
        }

        Logger.LogInformation("Processing complete.");

        return Task.FromResult($"Processed {sqsEvent.Records.Count} records.");
    }

    private void CreateContract(SQSEvent.SQSMessage record)
    {
        throw new NotImplementedException();
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
    /// Insert or updates the Contract into DynamoDB
    /// </summary>
    /// <param name="contract"></param>
    /// <returns></returns>
    [Tracing(SegmentName = "Create Contract")]
    private async Task PersistContract(Contract contract)
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