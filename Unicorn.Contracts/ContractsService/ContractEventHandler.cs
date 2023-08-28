// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using System;
using System.Collections.Generic;
using System.Net.WebSockets;
using System.Reflection.Metadata.Ecma335;
using System.Text.Json;
using System.Threading.Tasks;
using Amazon.DynamoDBv2;
using Amazon.DynamoDBv2.Model;
using Amazon.Lambda.Core;
using Amazon.Lambda.SQSEvents;
using Amazon.XRay.Recorder.Handlers.AwsSdk;
using AWS.Lambda.Powertools.Logging;
using AWS.Lambda.Powertools.Metrics;
using AWS.Lambda.Powertools.Tracing;

namespace Unicorn.Contracts.ContractService;

/// <summary>
/// 
/// </summary>
public class ContractEventHandler
{
    private readonly AmazonDynamoDBClient _dynamoDbClient;
    private readonly string _dynamodbTable = null!;

    /// <summary>
    /// Default constructor for ContractEventHandler
    /// </summary>
    public ContractEventHandler()
    {
        // Instrument all AWS SDK calls
        AWSSDKHandler.RegisterXRayForAllServices();
        _dynamoDbClient = new AmazonDynamoDBClient();

        _dynamodbTable = Environment.GetEnvironmentVariable("DYNAMODB_TABLE") ?? string.Empty;
        if (string.IsNullOrEmpty(_dynamodbTable))
        {
            throw new Exception("Environment variable DYNAMODB_TABLE is not defined.");
        }

        _dynamoDbClient = new AmazonDynamoDBClient();
        
    }
    
    /// <summary>
    /// Testing constructor for ContractEventHandler
    /// </summary>
    /// <param name="dynamoDbClient">Amazon DynamoDB Client object</param>
    public ContractEventHandler(AmazonDynamoDBClient dynamoDbClient)
    {
        _dynamoDbClient = dynamoDbClient;
        
        // _dynamoDbClient = new AmazonDynamoDBClient()
        // {
        //     Config =
        //     {
        //         Profile = { Name  = "Default"}
        //     }
        // };
        // _dynamodbTable =
        //     "uni-prop-local-contract-ContractsTable-17AH9W3IEUX2H";

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
        // Multiple records can be delivered in a single event
        Logger.LogInformation($"Beginning to process {sqsEvent.Records.Count} records...");

        foreach (var record in sqsEvent.Records)
        {
            var method = record.MessageAttributes["HttpMethod"].StringValue; //?? "No attribute with HttpMethod";
            Logger.LogInformation($"Identified HTTP Method : {method}");
            
            switch (method)
            {
                case "POST":
                    CreateContractAsync(record);
                    break;
                case "PUT":
                    UpdateContractAsync(record);
                    break;
                default:
                    Logger.LogInformation("Nothing to process.");
                    break;
            }
        }

        Logger.LogInformation("Processing complete.");

        return Task.FromResult($"Processed {sqsEvent.Records.Count} records.");
    }

    /// <summary>
    /// Create contract inside DynamoDB table
    /// Execution logic:
    ///  if contract does not exist
    ///  or contract status is either of [ CANCELLED | CLOSED | EXPIRED]
    ///  then create or replace contract with status = DRAFT
    ///  else
    ///  log exception message
    /// </summary>
    /// <param name="sqsMessage"></param>
    private async void CreateContractAsync(SQSEvent.SQSMessage sqsMessage)
    {
        Logger.LogInformation("Converting SQSMessage body to CreateContractRequest object.");
        Logger.LogInformation(sqsMessage.Body);
        var body = JsonSerializer.Deserialize<CreateContractRequest>(sqsMessage.Body, new JsonSerializerOptions()
        {
            PropertyNameCaseInsensitive = true
        });
        
        var contract = new Contract // ContractCreated and ContractLastModifiedOn set in constructor
        {
            PropertyId = body.PropertyId,
            ContractId = Guid.NewGuid(),
            Address = body?.Address,
            SellerName = body?.SellerName,
            ContractStatus = ContractStatus.Draft
        };
        
        try
        {
            Logger.LogInformation($"Creating new contract for Property ID: {contract.PropertyId}");

            var request = new PutItemRequest()
            {
                TableName = _dynamodbTable,
                ConditionExpression =
                    "attribute_not_exists(#property_id) OR (#contract_status IN ([:cs1, :cs2, :cs3]))",
                ExpressionAttributeNames = new Dictionary<string, string>
                {
                    { "#property_id", "PropertyId" },
                    { "#contract_status", "ContractStatus" }
                },
                ExpressionAttributeValues = new Dictionary<string, AttributeValue>
                {
                    { ":id", new AttributeValue { S = contract.PropertyId } },
                    { ":cs1", new AttributeValue { S = ContractStatus.Cancelled } },
                    { ":cs2", new AttributeValue { S = ContractStatus.Closed } },
                    { ":cs3", new AttributeValue { S = ContractStatus.Expired } },
                },
                Item = new Dictionary<string, AttributeValue>
                {
                    { "PropertyId", new AttributeValue { S = contract.PropertyId } },
                    { "ContractId", new AttributeValue { S = contract.ContractId.ToString("D") } },
                    { "Address", new AttributeValue { S = JsonSerializer.Serialize(contract.Address) } },
                    { "SellerName", new AttributeValue { S = contract.SellerName } },
                    { "ContractStatus", new AttributeValue { S = contract.ContractStatus } },
                    { "ContractCreated", new AttributeValue { S = contract.ContractCreated.ToString("O") } },
                    {
                        "ContractLastModifiedOn",
                        new AttributeValue { S = contract.ContractLastModifiedOn.ToString("O") }
                    }
                }
            };

            await _dynamoDbClient.PutItemAsync(request);
            
            // Add custom metric for "New Contracts"
            Metrics.AddMetric("NewContracts", 1, MetricUnit.Count, MetricResolution.Standard);
        }
        catch (Exception e)
        {
            Logger.LogError(e.Message);
            throw;
        }
    }

    private async void UpdateContractAsync(SQSEvent.SQSMessage sqsMessage)
    {
        var updateContractRequest = JsonSerializer.Deserialize<UpdateContractRequest>(sqsMessage.Body, new JsonSerializerOptions()
        {
            PropertyNameCaseInsensitive = true
        });

        Logger.LogInformation("Creating new contract");


        if (updateContractRequest == null)
        {
            Logger.LogError("Unable to Update contract. UpdateContractRequest is null.");
            return;
        }
        var request = new UpdateItemRequest()
        {
            TableName = _dynamodbTable,
            Key = new Dictionary<string, AttributeValue>
            {
                { "PropertyId", new AttributeValue { S = updateContractRequest.PropertyId } }
            },
            UpdateExpression = "SET #contract_status=:cs, #modified_date=:md",
            ExpressionAttributeNames = new Dictionary<string, string>
            {
                { "#modified_date", "ContractLastModifiedOn" },
                { "#contract_status", "ContractStatus" }
            },
            ExpressionAttributeValues = new Dictionary<string, AttributeValue>
            {
                { ":md", new AttributeValue { S = DateTime.Now.ToString("O") } },
                { ":cs", new AttributeValue { S = ContractStatus.Approved } }
            },
            ReturnValues = "UPDATED_NEW"
        };
        
        await _dynamoDbClient.UpdateItemAsync(request);
        
        Logger.LogInformation($"Contract {updateContractRequest.PropertyId} updated successfully.");
    }
}