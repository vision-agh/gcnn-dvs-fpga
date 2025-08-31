#include <fstream>
#include <vector>
#include <iostream>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <cstdlib>
#include <cstdint>

//using namespace std;

int main()
{

    int input_dim1 = 512;
    int output_dim1 = 1024;

    // Read weights
    std::vector<float> weights1(output_dim1 * input_dim1);
    std::ifstream w_file1("linear1_w.bin", std::ios::binary);
    if (w_file1.read(reinterpret_cast<char*>(weights1.data()), weights1.size() * sizeof(float))) {
        std::cout << "Weights loaded.\n";
    }
    
    // Read bias
    std::vector<float> bias1(output_dim1);
    std::ifstream b_file1("linear1_b.bin", std::ios::binary);
    if (b_file1.read(reinterpret_cast<char*>(bias1.data()), bias1.size() * sizeof(float))) {
        std::cout << "Bias loaded.\n";
    }


    int input_dim2 = 1024;
    int output_dim2 = 4;

    // Read weights
    std::vector<float> weights2(output_dim2 * input_dim2);
    std::ifstream w_file2("linear2_w.bin", std::ios::binary);
    if (w_file2.read(reinterpret_cast<char*>(weights2.data()), weights2.size() * sizeof(float))) {
        std::cout << "Weights loaded.\n";
    }

    // Read bias
    std::vector<float> bias2(output_dim2);
    std::ifstream b_file2("linear2_b.bin", std::ios::binary);
    if (b_file2.read(reinterpret_cast<char*>(bias2.data()), bias2.size() * sizeof(float))) {
        std::cout << "Bias loaded.\n";
    }
    
    
    int fd = open("/dev/mem", O_RDONLY | O_SYNC);
    if (fd < 0) {
        perror("open");
        return 1;
    }

    int data_in = 0;
    unsigned int prev_val = 0;
    unsigned int val = 0;
    unsigned int start_addr = 0xa0000000;
    unsigned int page_size = 16384;
    unsigned int page_base = start_addr & ~(page_size - 1);
    unsigned int page_offset = start_addr - page_base;
    
    void* map_base = mmap(0, page_size, PROT_READ, MAP_SHARED, fd, page_base);
    if (map_base == (void*)-1) {
        std::perror("mmap");
        close(fd);
        return 1;
    }
        
    volatile unsigned int* ptr = (volatile unsigned int*)((char*)map_base + page_offset);
    
    
    int features[4][input_dim1];
    float max_features[input_dim1];
    
    float output_vals2_sum[output_dim2];
    //int zero_point = 106;
    //float mult = 0.062758118;
    //float mult = 0.065889716;
    //int zero_point = 110;
    float mult = 0.051686693;
    int zero_point = 107;
    int cnt = 0;

   for(int i = 0; i < output_dim2; i++)
	output_vals2_sum[i] = 0;
    
    while(1)
    {	
    	//while(cnt % 1 != 0)
    	//{	
		//val = ptr[128];
		//val = ptr[129];
		
		//val = ptr[127];
		//std::cout << "waiting... prev_val = " << prev_val << ", val = " << val << std::endl;
		//std::cout << "Adres 0x" << std::hex << (start_addr + 127*4) << ": 0x" << val << std::endl;
		val = ptr[128];
		//std::cout << "waiting... prev_val = " << prev_val << ", val = " << val << std::endl;
		//std::cout << "Adres 0x" << std::hex << (start_addr + 128*4) << ": 0x" << val << std::endl;

		val = ptr[128];
		//std::cout << "waiting... prev_val = " << prev_val << ", val = " << val << std::endl;
		//std::cout << "Adres 0x" << std::hex << (start_addr + 128*4) << ": 0x" << val << std::endl;

		if(val == 1)
		{
		    //std::cout << "Rising edge detected" << std::endl;
		    
		    for(int i = 0; i < input_dim1; i++)
		    {
			features[0][i] = -1000000;
			features[1][i] = -1000000;
			features[2][i] = -1000000;
			features[3][i] = -1000000;
			max_features[i] = -1000000;
		    }
		    
		    //usleep(1);
		    
		    /*for (int i = 0; i < 513; i++) // 8 * 4B = 32B
		    {
			unsigned int value = ptr[i];
			std::cout << "Adres 0x" << std::hex << (start_addr + i*4) << ": 0x" << value << std::endl;	             
		    }*/
		    unsigned int value;
		    for (int i = 512; i < 2560; i++) // 8 * 4B = 32B   513 2561
		    {
			value = ptr[i];
			value = ptr[i];
			//std::cout << "Adres 0x" << std::hex << (start_addr + i*4) << ": 0x" << value << std::endl;
			//std::cout << ": 0x" << value << " ";
			features[int((i) / 512) - 1][(i) % 512] = value;	        
		    }
		    
		    //std::cout << std::endl;
		    //std::cout << "Values after max operation: " << std::endl;
		    
		    for(int i = 0; i < 512; i++)
		    {
		    	int max1 = features[0][i] >= features[1][i] ? features[0][i] : features[1][i];
		        int max2 = features[2][i] >= features[3][i] ? features[2][i] : features[3][i];
		        max_features[i] = max1 >= max2 ? max1 : max2;
		        //std::cout << max_features[i] << " ";
		        max_features[i] = (max_features[i] - zero_point) * mult;
		    }
		    //std::cout << std::endl;
		    
		    //std::cout << "Values after max dequantisation: " << std::endl;
		    // for(int i = 0; i < 512; i++)
		    // {
		    // 	std::cout << max_features[i] << " ";
		    // }
		    //std::cout << std::endl;

		    float output_vals1[output_dim1];

		    for(int i = 0; i < output_dim1; i++)
		        output_vals1[i] = 0;

		    for(int out = 0; out < output_dim1; out++)
		    {
		        float sum = 0;
		        for(int w = 0; w < input_dim1; w++)
		        {
		            sum += weights1[out * input_dim1 + w] * max_features[w];
		        }
		        output_vals1[out] = sum + bias1[out] < 0 ? 0 : sum + bias1[out];
		    }


		    // std::cout << "Values after first linear layer: " << std::endl;
		    // for(int i = 0; i < output_dim1; i++)
		    // {
		    // 	std::cout << output_vals1[i] << " ";
		    // }
		    // std::cout << std::endl;

		    float output_vals2[output_dim2];

		    for(int i = 0; i < output_dim2; i++)
		        output_vals2[i] = 0;

		    //std::cout << "Values after second linear layer: ";
		    
		    for(int out = 0; out < output_dim2; out++)
		    {
		        float sum = 0;
		        for(int w = 0; w < input_dim2; w++)
		        {
		            sum += weights2[out * input_dim2 + w] * output_vals1[w];
		        }
		        output_vals2[out] = sum + bias2[out];
		        output_vals2_sum[out] = output_vals2[out];
		        //std::cout << output_vals2[out] << " ";
		    }
		    //std::cout << std::endl;

		    //std::cout << "\r Predicted class: " << index1 << std::endl;
		    //std::cout << "\r Predicted class: " << index1 << " (top 3): " << index1 << ", " << index2 << ", " << index3 << std::flush;
		    //std::cout << "Predicted class (top 3): " << index1 << ", " << index2 << ", " << index3 << std::endl;
		//}
		
		
		//std::cout << "Info register" << std::hex << (start_addr + 256) << ": 0x" << val << std::endl;
		
		/*for (int i = 0; i < 4096; i++)
		{ // 8 * 4B = 32B
		    unsigned int val = ptr[i];
		    std::cout << "Adres 0x" << std::hex << (start_addr + i*4) << ": 0x" << val << std::endl;
		}*/
		
			prev_val = val;
			//usleep(5000000);
			usleep(1);
			//usleep(1000000);
		}
	int index1 = 0;
	int value1 = -1000000;
	for(int i = 0; i < output_dim2; i++)
	{
	    if(output_vals2_sum[i] > value1)
		{
		    value1 = output_vals2_sum[i];
		    index1 = i;
		}
	}

	// int index2 = 0;
	// int value2 = -1000000;
	// for(int i = 0; i < output_dim2; i++)
	// {
	// if(output_vals2_sum[i] > value2 && i != index1)
	//    {
	//        value2 = output_vals2_sum[i];
	//        index2 = i;
	//    }
	// }

	// int index3 = 0;
    //     int value3 = -1000000;
	//    for(int i = 0; i < output_dim2; i++)
	//     {
	// 	if(output_vals2_sum[i] > value3 && i != index1 && i != index2)
	// 	{
	// 	    value3 = output_vals2_sum[i];
	// 	    index3 = i;
	// 	}
	// }

	if (index1 == 0) {
		std::cout << "\r DVS plays paper!"  << std::endl;
		cnt = 0;
	}
	if (index1 == 1) {
		std::cout << "\r DVS plays scissors!"  << std::endl;
		cnt = 0;
	}
	if (index1 == 2) {
		std::cout << "\r DVS plays rock!"  << std::endl;
		cnt = 0;
	}
	if (index1 == 3) {
		cnt = cnt + 1;
	}
	if (index1 == 3 && cnt > 9) {
		cnt = cnt + 1;
		std::cout << "\r Let's play Rock-Paper-Scissors! Are you ready?"  << std::endl;
	}

	//std::cout << "\r Predicted class: " << index1 << " (top 3): " << index1 << ", " << index2 << ", " << index3 << std::endl;
	//usleep(50000);
	//cnt = 1;

   	for(int i = 0; i < output_dim2; i++)
		output_vals2_sum[i] = 0;
	
    }

    munmap(map_base, page_size);
    close(fd);

    return 0;
}

