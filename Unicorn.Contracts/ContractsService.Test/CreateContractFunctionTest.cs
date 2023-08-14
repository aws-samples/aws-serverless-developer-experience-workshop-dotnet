// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using System;
using System.Collections.Generic;
using System.Net;
using System.Threading.Tasks;
using Amazon.DynamoDBv2.DataModel;
using Amazon.Lambda.APIGatewayEvents;
using NSubstitute;
using Xunit;
using Xunit.Abstractions;

[assembly: CollectionBehavior(DisableTestParallelization = true)]

namespace Unicorn.Contracts.ContractService.Tests;

[Collection("Sequential")]
public class CreateContractFunctionTest
{
    private readonly ITestOutputHelper _testOutputHelper;

    public CreateContractFunctionTest(ITestOutputHelper testOutputHelper)
    {
        _testOutputHelper = testOutputHelper;
        
        // Set env variable for Powertools Metrics 
        Environment.SetEnvironmentVariable("POWERTOOLS_METRICS_NAMESPACE","ContractService");
    }

    [Fact]
    public async Task CreateValidContractPublishesDraftContractStatusChangedEvent()
    {
        // Arrange
        var request = TestHelpers.LoadApiGatewayProxyRequest("./events/create_valid_event.json");

        var mockDynamoDbContext = Substitute.For<IDynamoDBContext>();

        var mockPublisher = Substitute.For<IPublisher>();
        
        var context = TestHelpers.NewLambdaContext();

        var expectedResponse = new APIGatewayProxyResponse
        {
            StatusCode = (int)HttpStatusCode.OK,
            Headers = new Dictionary<string, string> { { "Content-Type", "application/json" } }
        };
        
        var function =
            new CreateContractFunction(mockDynamoDbContext, mockPublisher);

        var response = await function.FunctionHandler(request, context);

        await mockPublisher.Received(1).PublishEvent(Arg.Any<Contract>());

        _testOutputHelper.WriteLine("Lambda Response: \n" + response.Body);
        _testOutputHelper.WriteLine("Expected Response: \n" + expectedResponse.Body);

        Assert.Equal(expectedResponse.Headers, response.Headers);
        Assert.Equal(expectedResponse.StatusCode, response.StatusCode);
    }
}