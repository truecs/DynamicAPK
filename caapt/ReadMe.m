    从aapt资源打包源码流程角度，a.讲解该过程的中何时会生成应用程序包的package ID,b.然后如何进行修改。
    aapt首先根据命令行参数路径，寻找到androidmanifest文件，提取出应用程序的名称，创建resourceTable.
    具体调用路径main（main.cpp）-->handleCommand（command.cpp）->doPackage-->buildResources(Resource.cpp)
    
    status_t buildResources(Bundle* bundle, const sp<AaptAssets>& assets)
{
    // First, look for a package file to parse. This is required to
    // be able to generate the resource information.
    sp<AaptGroup> androidManifestFile =
            assets->getFiles().valueFor(String8("AndroidManifest.xml"));
    if (androidManifestFile == NULL) {
        fprintf(stderr, "ERROR: No AndroidManifest.xml file found.\n");
        return UNKNOWN_ERROR;
    }

    status_t err = parsePackage(bundle, assets, androidManifestFile);
    if (err != NO_ERROR) {
        return err;
    }

    NOISY(printf("Creating resources for package %s\n",
                 assets->getPackage().string()));

    ResourceTable table(bundle, String16(assets->getPackage()));
    err = table.addIncludedResources(bundle, assets);
    
    从第9行到第24行，我们需要关注的过程主要是读取androidManifest.xml内的应用名称（parsePackage比较麻烦，
    它会收集工程XML文件的元素<资源>信息，并对XML进行扁平压缩，最终写入到ResXMLTree的数据结构中），来创建
    一个资源表Resourcetable(资源打包最后阶段会根据该内容生成资源索引表resources.arsc),在上述代码第25行，
    我们能看到table.addIncludedResources(bundle, assets);该函数主要是用于添加被引用的资源包，当然一般
    是系统资源包android.jar.
    
    
    
    status_t ResourceTable::addIncludedResources(Bundle* bundle, const sp<AaptAssets>& assets)
{
    status_t err = assets->buildIncludedResources(bundle);
    if (err != NO_ERROR) {
        return err;
    }

    // For future reference to included resources.
    mAssets = assets;

    const ResTable& incl = assets->getIncludedResources();

    // Retrieve all the packages.
    const size_t N = incl.getBasePackageCount();
    for (size_t phase=0; phase<2; phase++) {
        for (size_t i=0; i<N; i++) {
            String16 name(incl.getBasePackageName(i));
            uint32_t id = incl.getBasePackageId(i);
            // First time through: only add base packages (id
            // is not 0); second time through add the other
            // packages.
            if (phase != 0) {
                if (id != 0) {
                    // Skip base packages -- already one.
                    id = 0;
                } else {
                    // Assign a dynamic id.
                    id = mNextPackageId;
                }
            } else if (id != 0) {
                if (id == 127) {
                    if (mHaveAppPackage) {
                        fprintf(stderr, "Included resources have two application packages!\n");
                        return UNKNOWN_ERROR;
                    }
                    mHaveAppPackage = true;
                }
                if (mNextPackageId > id) {
                    fprintf(stderr, "Included base package ID %d already in use!\n", id);
                    return UNKNOWN_ERROR;
                }
            }
            if (id != 0) {
                NOISY(printf("Including package %s with ID=%d\n",
                             String8(name).string(), id));
                sp<Package> p = new Package(name, id);
                mPackages.add(name, p);
                mOrderedPackages.add(p);

                if (id >= mNextPackageId) {
                    mNextPackageId = id+1;
                }
            }
        }
    }

    // Every resource table always has one first entry, the bag attributes.
    const SourcePos unknown(String8("????"), 0);
    sp<Type> attr = getType(mAssetsPackage, String16("attr"), unknown);

    return NO_ERROR;
}

从上述代码48行到第89行，描述了添加引用依赖包的过程，核心在第80-82行，以Pair的格式存入依赖包（注意ID为包命名空间8位二进制，系统层为1）。
        从第93行getType()开始就要进入到当前资源包ID的命名了，ResourceTable::getType()---》call ResourceTable::getPackages()
        
        
        
        
      
sp<ResourceTable::Package> ResourceTable::getPackage(const String16& package)
{
    sp<Package> p = mPackages.valueFor(package);
    if (p == NULL) {
        if (mBundle->getIsOverlayPackage()) {
            p = new Package(package, 0x00);
        } else if (mIsAppPackage) {
            if (mHaveAppPackage) {
                fprintf(stderr, "Adding multiple application package resources; only one is allowed.\n"
                                "Use -x to create extended resources.\n");
                return NULL;
            }
            mHaveAppPackage = true;
            p = new Package(package, 127);
        } else {
            p = new Package(package, mNextPackageId);
        }
        //printf("*** NEW PACKAGE: \"%s\" id=%d\n",
        // String8(package).string(), p->getAssignedId());
        mPackages.add(package, p);
        mOrderedPackages.add(p);
        mNextPackageId++;
    }
    return p;
}
在这里我们应用程序的ID赋值在第118行，最终在第124行到125行完成对新包的加入，代码相对比较简单，不再进行赘述，至此，应用程序的包ID被赋值为0x7f(127).
至此大概知道如何修改源码了，可以把127换成一个其它数字。我们只需要对bundle数据结构进行扩展，将ID-127换成从bundle读入的一个变量即可。


